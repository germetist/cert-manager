# CRI_ARCH is meant for M1 users. By default, the images loaded into the local
# cluster when running 'make -j e2e-setup' will match the architecture detected
# by "uname -m" (e.g., arm64). Note that images that don't have an arm64
# version are loaded as amd64. To force the use of amd64 images for all the
# images, use:
#
#   make install CRI_ARCH=amd64
#
CRI_ARCH := $(HOST_ARCH)

# TODO: this version is also defaulted in ./make/cluster.sh. Make it so that it
# is set in one place only.
K8S_VERSION := 1.24

IMAGE_ingressnginx_amd64 := k8s.gcr.io/ingress-nginx/controller:v1.1.0@sha256:7464dc90abfaa084204176bcc0728f182b0611849395787143f6854dc6c38c85
IMAGE_kyverno_amd64 := ghcr.io/kyverno/kyverno:v1.3.6@sha256:7d7972e7d9ed2a6da27b06ccb1c3c5d3544838d6cedb67a050ba7d655461ef52
IMAGE_kyvernopre_amd64 := ghcr.io/kyverno/kyvernopre:v1.3.6@sha256:94fc7f204917a86dcdbc18977e843701854aa9f84c215adce36c26de2adf13df
IMAGE_vault_amd64 := index.docker.io/library/vault:1.2.3@sha256:b1c86c9e173f15bb4a926e4144a63f7779531c30554ac7aee9b2a408b22b2c01
IMAGE_bind_amd64 := docker.io/eafxx/bind:latest-9f74179f@sha256:0b8c766f5bedbcbe559c7970c8e923aa0c4ca771e62fcf8dba64ffab980c9a51
IMAGE_sampleexternalissuer_amd64 := ghcr.io/cert-manager/sample-external-issuer/controller:v0.1.1@sha256:7dafe98c73d229bbac08067fccf9b2884c63c8e1412fe18f9986f59232cf3cb5
IMAGE_projectcontour_amd64 := docker.io/projectcontour/contour:v1.20.1@sha256:10f6501cbb8514549b2ae71634152fa1a02e4ba63a9a32955d2ff027a0da1254
IMAGE_pebble_amd64 := local/pebble:local
IMAGE_vaultretagged_amd64 := local/vault:local

IMAGE_ingressnginx_arm64 := k8s.gcr.io/ingress-nginx/controller:v1.1.0@sha256:86be28e506653cbe29214cb272d60e7c8841ddaf530da29aa22b1b1017faa956
IMAGE_kyverno_arm64 := ghcr.io/kyverno/kyverno:v1.3.6@sha256:fa1e44e927433f217ef507299aeebf27f9b24a21a5f27d07b3b8acf26b48d5e6
IMAGE_kyvernopre_arm64 := ghcr.io/kyverno/kyvernopre:v1.3.6@sha256:f1a85fb6a95ccc9770e668116e0252c7e7c42b6403f3451047e154b8367cb987
IMAGE_vault_arm64 := index.docker.io/library/vault:1.2.3@sha256:226a269b83c4b28ff8a512e76f1e7b707eccea012e4c3ab4c7af7fff1777ca2d
IMAGE_bind_arm64 := docker.io/eafxx/bind:latest-9f74179f@sha256:85de273f24762c0445035d36290a440e8c5a6a64e9ae6227d92e8b0b0dc7dd6d
IMAGE_sampleexternalissuer_arm64 := # 🚧 NOT AVAILABLE FOR arm64 🚧
IMAGE_projectcontour_arm64 := docker.io/projectcontour/contour:v1.20.1@sha256:19c453cbd127e62ff24a2d5a48f4bd2567f04ebcf499df711663db7a0a275303
IMAGE_pebble_arm64 := local/pebble:local
IMAGE_vaultretagged_arm64 := local/vault:local

IMAGE_kind_amd64 := $(shell make/cluster.sh --show-image)
IMAGE_kind_arm64 := $(IMAGE_kind_amd64)

PEBBLE_COMMIT = ba5f81dd80fa870cbc19326f2d5a46f45f0b5ee3
GATEWAY_API_VERSION = 0.4.1

.PHONY: e2e-setup-kind
## Create a Kubernetes cluster using Kind, which is required for `make e2e`.
## The Kind image is pre-pulled to avoid 'kind create' from blocking other make
## targets.
##
##	make kind [KIND_CLUSTER_NAME=name] [K8S_VERSION=<kubernetes_version>]
##
## @category Development
e2e-setup-kind: kind-exists
	@printf "✅  \033[0;32mReady\033[0;0m. The next step is to install cert-manager and the addons with the command:\n" >&2
	@printf "    \033[0;36mmake -j e2e-setup\033[0;0m\n" >&2

# This is the actual target that creates the kind cluster.
#
# The presence of the file bin/scratch/kind-exists indicates that your kube
# config's current context points to a kind cluster. The file contains the
# name of the kind cluster.
#
# We use FORCE instead of .PHONY because this is a real file that can be
# used as a prerequisite. If we were to use .PHONY, then the file's
# timestamp would not be used to check whether targets should be rebuilt,
# and they would get constantly rebuilt.
bin/scratch/kind-exists: make/config/kind/config.yaml make/config/kind/config_etcd_no_fsync.yaml preload-kind-image make/cluster.sh FORCE bin/tools/kind bin/tools/kubectl bin/tools/yq | bin/scratch
	@$(eval KIND_CLUSTER_NAME ?= kind)
	@make/cluster.sh --name $(KIND_CLUSTER_NAME)
	@if [ "$(shell cat $@ 2>/dev/null)" != kind ]; then echo kind > $@; else touch $@; fi

.PHONY: kind-exists
kind-exists: bin/scratch/kind-exists

#  Component                Used in                   IP                     A record in bind
#  ---------                -------                   --                     ----------------
#  e2e-setup-bind           DNS-01 tests              SERVICE_IP_PREFIX.16
#  e2e-setup-ingressnginx   HTTP-01 Ingress tests     SERVICE_IP_PREFIX.15   *.ingress-nginx.db.http01.example.com
#  e2e-setup-projectcontour HTTP-01 GatewayAPI tests  SERVICE_IP_PREFIX.14   *.gateway.db.http01.example.com
.PHONY: e2e-setup
## Installs cert-manager as well as components required for running the
## end-to-end tests. If the kind cluster does not already exist, it will be
## created.
##
## @category Development
e2e-setup: e2e-setup-gatewayapi e2e-setup-certmanager e2e-setup-kyverno e2e-setup-vault e2e-setup-bind e2e-setup-sampleexternalissuer e2e-setup-samplewebhook e2e-setup-pebble e2e-setup-ingressnginx e2e-setup-projectcontour

# The function "image-tar" returns the path to the image tarball for a given
# image name. For example:
#
#     $(call image-tar, kyverno)
#
# returns the following path:
#
#     bin/downloaded/containers/amd64/docker.io/kyverno+2.4.9@sha256+bfba204252.tar
#                               <---> <--------------------------------------->
#                              CRI_ARCH         IMAGE_kyverno_amd64
#                                           (with ":" replaced with "+")
#
# Note the "+" signs. We replace all the "+" with ":" because ":" can't be used
# in make targets. The "+" replacement is safe since it isn't a valid character
# in image names.
#
# When an image isn't available, i.e., IMAGE_imagename_arm64 is empty, we still
# return a string of the form "bin/downloaded/containers/amd64/missing-imagename.tar".
define image-tar
bin/downloaded/containers/$(CRI_ARCH)/$(if $(IMAGE_$(1)_$(CRI_ARCH)),$(subst :,+,$(IMAGE_$(1)_$(CRI_ARCH))),missing-$(1)).tar
endef

# Let's separate the pulling of the Kind image so that more tasks can be
# run in parallel when running "make -j e2e-setup". In CI, the Docker
# engine being stripped on every job, we save the kind image to
# "bin/downloads". Side note: we don't use "$(CI)" directly since we would
# get the message "warning: undefined variable 'CI'".
.PHONY: preload-kind-image
ifeq ($(shell printenv CI),)
preload-kind-image: bin/tools/crane
	@$(CTR) inspect $(IMAGE_kind_$(CRI_ARCH)) 2>/dev/null >&2 || (set -x; $(CTR) pull $(IMAGE_kind_$(CRI_ARCH)))
else
preload-kind-image: $(call image-tar,kind) bin/tools/crane
	$(CTR) inspect $(IMAGE_kind_$(CRI_ARCH)) 2>/dev/null >&2 || $(CTR) load -i $<
endif

LOAD_TARGETS=load-$(call image-tar,ingressnginx) load-$(call image-tar,kyverno) load-$(call image-tar,kyvernopre) load-$(call image-tar,vault) load-$(call image-tar,bind) load-$(call image-tar,projectcontour) load-$(call image-tar,sampleexternalissuer) load-$(call image-tar,vaultretagged) load-bin/downloaded/containers/$(CRI_ARCH)/pebble.tar load-bin/downloaded/containers/$(CRI_ARCH)/samplewebhook.tar load-bin/containers/cert-manager-controller-linux-$(CRI_ARCH).tar load-bin/containers/cert-manager-acmesolver-linux-$(CRI_ARCH).tar load-bin/containers/cert-manager-cainjector-linux-$(CRI_ARCH).tar load-bin/containers/cert-manager-webhook-linux-$(CRI_ARCH).tar load-bin/containers/cert-manager-ctl-linux-$(CRI_ARCH).tar
.PHONY: $(LOAD_TARGETS)
$(LOAD_TARGETS): load-%: % bin/scratch/kind-exists bin/tools/kind
	bin/tools/kind load image-archive --name=$(shell cat bin/scratch/kind-exists) $*

# We use crane instead of docker when pulling images, which saves some time
# since we don't care about having the image available to docker.
#
# We don't pull using both the digest and tag because crane replaces the
# tag with "i-was-a-digest". We still check that the downloaded image
# matches the digest.
$(call image-tar,kyverno) $(call image-tar,kyvernopre) $(call image-tar,bind) $(call image-tar,projectcontour) $(call image-tar,sampleexternalissuer) $(call image-tar,vault) $(call image-tar,ingressnginx): bin/downloaded/containers/$(CRI_ARCH)/%.tar: bin/tools/crane
	@$(eval IMAGE=$(subst +,:,$*))
	@$(eval IMAGE_WITHOUT_DIGEST=$(shell cut -d@ -f1 <<<"$(IMAGE)"))
	@$(eval DIGEST=$(subst $(IMAGE_WITHOUT_DIGEST)@,,$(IMAGE)))
	@mkdir -p $(dir $@)
	diff <(echo "$(DIGEST)  -" | cut -d: -f2) <(bin/tools/crane manifest --platform=linux/$(CRI_ARCH) $(IMAGE) | sha256sum)
	bin/tools/crane pull $(IMAGE_WITHOUT_DIGEST) $@ --platform=linux/$(CRI_ARCH)

# Same as above, except it supports multiarch images.
$(call image-tar,kind): bin/downloaded/containers/$(CRI_ARCH)/%.tar: bin/tools/crane
	@$(eval IMAGE=$(subst +,:,$*))
	@$(eval IMAGE_WITHOUT_DIGEST=$(shell cut -d@ -f1 <<<"$(IMAGE)"))
	@$(eval DIGEST=$(subst $(IMAGE_WITHOUT_DIGEST)@,,$(IMAGE)))
	@mkdir -p $(dir $@)
	diff <(echo "$(DIGEST)  -" | cut -d: -f2) <(bin/tools/crane manifest $(IMAGE) | sha256sum)
	bin/tools/crane pull $(IMAGE_WITHOUT_DIGEST) $@ --platform=linux/$(CRI_ARCH)

# Since we dynamically install Vault via Helm during the end-to-end tests,
# we need its image to be retagged to a well-known tag "local/vault:local".
$(call image-tar,vaultretagged): $(call image-tar,vault)
	@mkdir -p /tmp/vault $(dir $@)
	tar xf $< -C /tmp/vault
	cat /tmp/vault/manifest.json | jq '.[0].RepoTags |= ["local/vault:local"]' -r > /tmp/vault/temp
	mv /tmp/vault/temp /tmp/vault/manifest.json
	tar cf $@ -C /tmp/vault .
	@rm -rf /tmp/vault

FEATURE_GATES ?= AdditionalCertificateOutputFormats=true,ExperimentalCertificateSigningRequestControllers=true,ExperimentalGatewayAPISupport=true,ServerSideApply=true,LiteralCertificateSubject=true

# In make, there is no way to escape commas or spaces. So we use the
# variables $(space) and $(comma) instead.
null  =
space = $(null) #
comma = ,

# Helm's "--set" interprets commas, which means we want to escape commas
# for "--set featureGates". That's why we have "\$(comma)".
feature_gates_controller := $(subst $(space),\$(comma),$(filter AllAlpha=% AllBeta=% AdditionalCertificateOutputFormats=% ValidateCAA=% ExperimentalCertificateSigningRequestControllers=% ExperimentalGatewayAPISupport=% ServerSideApply=% LiteralCertificateSubject=%, $(subst $(comma),$(space),$(FEATURE_GATES))))
feature_gates_webhook := $(subst $(space),\$(comma),$(filter AllAlpha=% AllBeta=% AdditionalCertificateOutputFormats=% LiteralCertificateSubject=%,   $(subst $(comma),$(space),$(FEATURE_GATES))))
feature_gates_cainjector := $(subst $(space),\$(comma),$(filter AllAlpha=% AllBeta=%, $(subst $(comma),$(space),$(FEATURE_GATES))))

.PHONY: e2e-setup-certmanager
e2e-setup-certmanager: bin/cert-manager.tgz $(foreach bin,controller acmesolver cainjector webhook ctl,bin/containers/cert-manager-$(bin)-linux-$(CRI_ARCH).tar) $(foreach bin,controller acmesolver cainjector webhook ctl,load-bin/containers/cert-manager-$(bin)-linux-$(CRI_ARCH).tar) e2e-setup-gatewayapi bin/scratch/kind-exists bin/tools/kubectl bin/tools/kind
	@$(eval SERVICE_IP_PREFIX = $(shell bin/tools/kubectl cluster-info dump | grep -m1 ip-range | cut -d= -f2 | cut -d. -f1,2,3))
	@$(eval TAG = $(shell tar xfO bin/containers/cert-manager-controller-linux-$(CRI_ARCH).tar manifest.json | jq '.[0].RepoTags[0]' -r | cut -d: -f2))
	bin/tools/helm upgrade \
		--install \
		--create-namespace \
		--wait \
		--namespace cert-manager \
		--set image.repository="$(shell tar xfO bin/containers/cert-manager-controller-linux-$(CRI_ARCH).tar manifest.json | jq '.[0].RepoTags[0]' -r | cut -d: -f1)" \
		--set cainjector.image.repository="$(shell tar xfO bin/containers/cert-manager-cainjector-linux-$(CRI_ARCH).tar manifest.json | jq '.[0].RepoTags[0]' -r | cut -d: -f1)" \
		--set webhook.image.repository="$(shell tar xfO bin/containers/cert-manager-webhook-linux-$(CRI_ARCH).tar manifest.json | jq '.[0].RepoTags[0]' -r | cut -d: -f1)" \
		--set startupapicheck.image.repository="$(shell tar xfO bin/containers/cert-manager-ctl-linux-$(CRI_ARCH).tar manifest.json | jq '.[0].RepoTags[0]' -r | cut -d: -f1)" \
		--set image.tag="$(TAG)" \
		--set cainjector.image.tag="$(TAG)" \
		--set webhook.image.tag="$(TAG)" \
		--set startupapicheck.image.tag="$(TAG)" \
		--set installCRDs=true \
		--set featureGates="$(feature_gates_controller)" \
		--set "webhook.extraArgs={--feature-gates=$(feature_gates_webhook)}" \
		--set "cainjector.extraArgs={--feature-gates=$(feature_gates_cainjector)}" \
		--set "extraArgs={--dns01-recursive-nameservers=$(SERVICE_IP_PREFIX).16:53,--dns01-recursive-nameservers-only=true,--acme-http01-solver-image=cert-manager-acmesolver-$(CRI_ARCH):$(TAG)}" \
		cert-manager $< >/dev/null

.PHONY: e2e-setup-bind
e2e-setup-bind: $(call image-tar,bind) load-$(call image-tar,bind) $(wildcard make/config/bind/*.yaml) bin/scratch/kind-exists bin/tools/kubectl
	@$(eval SERVICE_IP_PREFIX = $(shell bin/tools/kubectl cluster-info dump | grep -m1 ip-range | cut -d= -f2 | cut -d. -f1,2,3))
	@$(eval IMAGE = $(shell tar xfO $< manifest.json | jq '.[0].RepoTags[0]' -r))
	bin/tools/kubectl get ns bind 2>/dev/null >&2 || bin/tools/kubectl create ns bind
	sed -e "s|{SERVICE_IP_PREFIX}|$(SERVICE_IP_PREFIX)|g" -e "s|{IMAGE}|$(IMAGE)|g" make/config/bind/*.yaml | bin/tools/kubectl apply -n bind -f - >/dev/null

.PHONY: e2e-setup-gatewayapi
e2e-setup-gatewayapi: bin/downloaded/gatewayapi-v$(GATEWAY_API_VERSION) bin/scratch/kind-exists bin/tools/kubectl
	bin/tools/kubectl kustomize $</*/config/crd | bin/tools/kubectl apply -f - >/dev/null


# v1 NGINX-Ingress by default only watches Ingresses with Ingress class
# defined. When configuring solver block for ACME HTTTP01 challenge on an
# ACME issuer, cert-manager users can currently specify either an Ingress
# name or a class. We also e2e test these two ways of creating Ingresses
# with ingress-shim. For the ingress controller to watch our Ingresses that
# don't have a class, we pass a --watch-ingress-without-class flag:
# https://github.com/kubernetes/ingress-nginx/blob/main/charts/ingress-nginx/values.yaml#L64-L67
.PHONY: e2e-setup-ingressnginx
e2e-setup-ingressnginx: $(call image-tar,ingressnginx) load-$(call image-tar,ingressnginx) bin/tools/helm
	@$(eval SERVICE_IP_PREFIX = $(shell bin/tools/kubectl cluster-info dump | grep -m1 ip-range | cut -d= -f2 | cut -d. -f1,2,3))
	@$(eval TAG=$(shell tar xfO $< manifest.json | jq '.[0].RepoTags[0]' -r | cut -d: -f2))
	bin/tools/helm repo add ingress-nginx --force-update https://kubernetes.github.io/ingress-nginx >/dev/null
	bin/tools/helm upgrade \
		--install \
		--wait \
		--version 4.0.10 \
		--namespace ingress-nginx \
		--create-namespace \
		--set controller.image.tag=$(TAG) \
		--set controller.image.digest= \
		--set controller.image.pullPolicy=Never \
		--set controller.service.clusterIP=${SERVICE_IP_PREFIX}.15 \
		--set controller.service.type=ClusterIP \
		--set controller.config.no-tls-redirect-locations= \
		--set admissionWebhooks.enabled=false \
		--set controller.admissionWebhooks.enabled=true \
		--set controller.watchIngressWithoutClass=true \
		ingress-nginx ingress-nginx/ingress-nginx >/dev/null

.PHONY: e2e-setup-kyverno
e2e-setup-kyverno: $(call image-tar,kyverno) $(call image-tar,kyvernopre) load-$(call image-tar,kyverno) load-$(call image-tar,kyvernopre) make/config/kyverno/policy.yaml bin/scratch/kind-exists e2e-setup-certmanager bin/tools/kubectl bin/tools/helm
	@$(eval TAG=$(shell tar xfO $< manifest.json | jq '.[0].RepoTags[0]' -r | cut -d: -f2))
	bin/tools/helm repo add kyverno --force-update https://kyverno.github.io/kyverno/ >/dev/null
	bin/tools/helm upgrade \
		--install \
		--wait \
		--namespace kyverno \
		--create-namespace \
		--version v1.3.6 \
		--set image.tag=v1.3.6 \
		--set initImage.tag=v1.3.6 \
		--set image.pullPolicy=Never \
		--set initImage.pullPolicy=Never \
		kyverno kyverno/kyverno >/dev/null
	@bin/tools/kubectl create ns cert-manager >/dev/null 2>&1 || true
	bin/tools/kubectl apply -f make/config/kyverno/policy.yaml >/dev/null

bin/downloaded/pebble-$(PEBBLE_COMMIT).tar.gz: | bin/downloaded
	curl -sSL https://github.com/letsencrypt/pebble/archive/$(PEBBLE_COMMIT).tar.gz -o $@

# We can't use GOBIN with "go install" because cross-compilation is not
# possible with go install. That's a problem when cross-compiling for
# linux/arm64 when running on darwin/arm64.
bin/downloaded/containers/$(CRI_ARCH)/pebble/pebble: bin/downloaded/pebble-$(PEBBLE_COMMIT).tar.gz $(DEPENDS_ON_GO)
	@mkdir -p $(dir $@)
	tar xzf $< -C $(dir $@)
	cd $(dir $@)pebble-$(PEBBLE_COMMIT) && GOOS=linux GOARCH=$(CRI_ARCH) CGO_ENABLED=$(CGO_ENABLED) GOMAXPROCS=$(GOBUILDPROCS) $(GOBUILD) $(GOFLAGS) -o $(CURDIR)/$@ ./cmd/pebble

bin/downloaded/containers/$(CRI_ARCH)/pebble.tar: bin/downloaded/containers/$(CRI_ARCH)/pebble/pebble make/config/pebble/Containerfile.pebble
	@$(eval BASE := BASE_IMAGE_controller-linux-$(CRI_ARCH))
	$(CTR) build --quiet \
		-f make/config/pebble/Containerfile.pebble \
		--build-arg BASE_IMAGE=$($(BASE)) \
		-t local/pebble:local \
		$(dir $<) >/dev/null
	$(CTR) save local/pebble:local -o $@ >/dev/null

.PHONY: e2e-setup-pebble
e2e-setup-pebble: load-bin/downloaded/containers/$(CRI_ARCH)/pebble.tar bin/scratch/kind-exists bin/tools/helm
	bin/tools/helm upgrade \
		--install \
		--wait \
		--namespace pebble \
		--create-namespace \
		pebble make/config/pebble/chart >/dev/null

bin/downloaded/containers/$(CRI_ARCH)/samplewebhook/samplewebhook: make/config/samplewebhook/sample/main.go $(DEPENDS_ON_GO)
	@mkdir -p $(dir $@)
	GOOS=linux GOARCH=$(CRI_ARCH) $(GOBUILD) -o $@ $(GOFLAGS) make/config/samplewebhook/sample/main.go

bin/downloaded/containers/$(CRI_ARCH)/samplewebhook.tar: bin/downloaded/containers/$(CRI_ARCH)/samplewebhook/samplewebhook make/config/samplewebhook/Containerfile.samplewebhook
	@$(eval BASE := BASE_IMAGE_controller-linux-$(CRI_ARCH))
	$(CTR) build --quiet \
		-f make/config/samplewebhook/Containerfile.samplewebhook \
		--build-arg BASE_IMAGE=$($(BASE)) \
		-t local/samplewebhook:local \
		$(dir $<) >/dev/null
	$(CTR) save local/samplewebhook:local -o $@ >/dev/null

.PHONY: e2e-setup-samplewebhook
e2e-setup-samplewebhook: load-bin/downloaded/containers/$(CRI_ARCH)/samplewebhook.tar e2e-setup-certmanager bin/scratch/kind-exists bin/tools/helm
	bin/tools/helm upgrade \
		--install \
		--wait \
		--namespace samplewebhook \
		--create-namespace \
		samplewebhook make/config/samplewebhook/chart >/dev/null

.PHONY: e2e-setup-projectcontour
e2e-setup-projectcontour: load-$(call image-tar,projectcontour) make/config/projectcontour/contour-gateway.yaml make/config/projectcontour/gateway.yaml bin/scratch/kind-exists bin/tools/kubectl bin/tools/ytt
	@$(eval SERVICE_IP_PREFIX = $(shell bin/tools/kubectl cluster-info dump | grep -m1 ip-range | cut -d= -f2 | cut -d. -f1,2,3))
	bin/tools/ytt --data-value service_ip_prefix="${SERVICE_IP_PREFIX}" \
		--file make/config/projectcontour/contour-gateway.yaml \
		--file make/config/projectcontour/gateway.yaml | bin/tools/kubectl apply -f-

.PHONY: e2e-setup-sampleexternalissuer
ifeq ($(CRI_ARCH),amd64)
e2e-setup-sampleexternalissuer: load-$(call image-tar,sampleexternalissuer) bin/scratch/kind-exists bin/tools/kubectl
	bin/tools/kubectl apply -n sample-external-issuer-system -f https://github.com/cert-manager/sample-external-issuer/releases/download/v0.1.1/install.yaml >/dev/null
	bin/tools/kubectl patch -n sample-external-issuer-system deployments.apps sample-external-issuer-controller-manager --type=json -p='[{"op": "add", "path": "/spec/template/spec/containers/1/imagePullPolicy", "value": "Never"}]' >/dev/null
else
e2e-setup-sampleexternalissuer:
	@printf "\033[0;33mWarning\033[0;0m: skipping the target \033[0;31m$@\033[0;0m because there exists no image for $(CRI_ARCH).\n" >&2
	@printf "The end-to-end tests that rely on sampleexternalissuer will fail. If you are using Docker Desktop,\n" >&2
	@printf "you can force using the amd64 image anyways by running:\n" >&2
	@printf "    \033[0;36mmake $@ CRI_ARCH=amd64\033[0;0m\n" >&2
	@printf "Note that this won't if you are using Colima, or Rancher Desktop, or minikube.\n" >&2
endif


# Note that the end-to-end tests are dealing with the Helm installation. We
# do not need to Helm install here.
.PHONY: e2e-setup-vault
e2e-setup-vault: load-$(call image-tar,vaultretagged) bin/scratch/kind-exists bin/tools/helm

# Exported because it needs to flow down to make/e2e.sh.
export ARTIFACTS ?= $(shell pwd)/bin/artifacts

.PHONY: kind-logs
kind-logs: bin/scratch/kind-exists bin/tools/kind
	rm -rf $(ARTIFACTS)/cert-manager-e2e-logs
	mkdir -p $(ARTIFACTS)/cert-manager-e2e-logs
	bin/tools/kind export logs $(ARTIFACTS)/cert-manager-e2e-logs --name=$(shell cat bin/scratch/kind-exists)

bin/scratch:
	@mkdir -p $@
