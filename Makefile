# GITHUB_USER containing '@' char must be escaped with '%40'
GITHUB_USER := $(shell echo $(GITHUB_USER) | sed 's/@/%40/g')
GITHUB_TOKEN ?=

USE_VENDORIZED_BUILD_HARNESS ?=

ifndef USE_VENDORIZED_BUILD_HARNESS
-include $(shell curl -s -H 'Authorization: token ${GITHUB_TOKEN}' -H 'Accept: application/vnd.github.v4.raw' -L https://api.github.com/repos/open-cluster-management/build-harness-extensions/contents/templates/Makefile.build-harness-bootstrap -o .build-harness-bootstrap; echo .build-harness-bootstrap)
else
-include vbh/.build-harness-vendorized
endif

BUILD_DIR ?= build

VERSION ?= 2.0.0
IMG ?= multiclusterhub-operator
SECRET_REGISTRY ?= quay.io
REGISTRY ?= quay.io/rhibmcollab
BUNDLE_REGISTRY ?= quay.io/open-cluster-management
GIT_VERSION ?= $(shell git describe --exact-match 2> /dev/null || \
                 git describe --match=$(git rev-parse --short=8 HEAD) --always --dirty --abbrev=8)

DOCKER_USER := $(shell echo $(DOCKER_USER))
DOCKER_PASS := $(shell echo $(DOCKER_PASS))
NAMESPACE ?= open-cluster-management

# For OCP OLM
export IMAGE ?= $(shell echo $(REGISTRY)/$(IMG):$(VERSION))
export CSV_CHANNEL ?= alpha
export CSV_VERSION ?= 2.0.0

# Use podman if available, otherwise use docker
ifeq ($(CONTAINER_ENGINE),)
	CONTAINER_ENGINE = $(shell podman version > /dev/null && echo podman || echo docker)
endif

.PHONY: lint image olm-catalog clean

all: clean lint test image

include common/Makefile.common.mk

lint: lint-all

image:
	./cicd-scripts/build.sh "$(REGISTRY)/$(IMG):$(VERSION)"

push:
	./common/scripts/push.sh "$(REGISTRY)/$(IMG):$(VERSION)"

olm-catalog: clean
	@common/scripts/olm_catalog.sh "$(BUNDLE_REGISTRY)" "$(IMG)" "$(VERSION)"

clean::
	rm -rf $(BUILD_DIR)/_output
	rm -f cover.out

install: image push olm-catalog
	# need to check for operator group
	@oc create secret docker-registry multiclusterhub-operator-pull-secret --docker-server=$(SECRET_REGISTRY) --docker-username=$(DOCKER_USER) --docker-password=$(DOCKER_PASS) || true
	@oc create secret docker-registry quay-secret --docker-server=$(SECRET_REGISTRY) --docker-username=$(DOCKER_USER) --docker-password=$(DOCKER_PASS) || true
	@oc apply -k ./build/_output/olm || true

install-dev:
	./common/scripts/tests/install.sh

directuninstall:
	@ oc delete -k ./build/_output/olm || true

uninstall: directuninstall unsubscribe

reinstall: uninstall install

local:
	@operator-sdk run --local --namespace="" --operator-flags="--zap-devel=true"

subscribe: image olm-catalog
	# @kubectl create secret docker-registry quay-secret --docker-server=$(REGISTRY) --docker-username=$(DOCKER_USER) --docker-password=$(DOCKER_PASS) || true
	@oc apply -f build/_output/olm/multiclusterhub.resources.yaml

unsubscribe:
	@oc delete MultiClusterHub example-multiclusterhub || true
	@oc delete appsub --all || true
	@oc delete helmrelease --all || true
	@oc delete MultiClusterHub example-multiclusterhub || true
	@oc delete hiveconfig hive || true
	@oc delete crd channels.app.ibm.com || true
	@oc delete crd deployables.app.ibm.com || true
	@oc delete crd subscriptions.app.ibm.com || true
	@oc delete crd etcdbackups.etcd.database.coreos.com || true
	@oc delete crd etcdclusters.etcd.database.coreos.com || true
	@oc delete crd etcdrestores.etcd.database.coreos.com || true
	@oc delete crd multiclusterhubs.operators.open-cluster-management.io || true
	@oc delete csv multiclusterhub-operator.v2.0.0 || true
	@oc delete csv etcdoperator.v0.9.4 || true
	@oc delete csv multicluster-operators-subscription.v0.1.5 || true
	@oc delete csv hive-operator.v1.0.4 || true
	@oc delete subscription multiclusterhub-operator || true
	@oc delete subscription etcdoperator.v0.9.4 || true
	@oc delete catalogsource multiclusterhub-operator-registry || true
	@oc delete deploy -n hive hive-controllers || true
	@oc delete deploy -n hive hiveadmission || true
	@oc delete apiservice v1.admission.hive.openshift.io || true
	@oc delete apiservice v1.hive.openshift.io || true
	@oc delete apiservice v1alpha1.clusterregistry.k8s.io || true
	@oc delete apiservice v1alpha1.mcm.ibm.com || true
	@oc delete apiservice v1beta1.mcm.ibm.com || true
	@oc delete apiservice v1beta1.webhook.certmanager.k8s.io || true
	@oc delete -k templates/multiclusterhub/base/hive/ || true
	@oc delete clusterrole hive-admin || true
	@oc delete clusterrole hive-reader || true
	@oc delete service multicluster-operators-subscription || true
	@oc delete helmreleases --all || true
	@oc delete validatingwebhookconfiguration cert-manager-webhook || true
	@oc delete clusterrole cert-manager-webhook-requester || true
	@oc delete clusterrolebinding cert-manager-webhook-auth-delegator || true
	@for crd in $(oc get crd | grep cert | cut -f 1 -d ' '); do oc delete crd $crd; done
	# Wrong syntax for Makefile @for webhook in $(oc get validatingwebhookconfiguration | grep hive | cut -f 1 -d ' '); do oc delete validatingwebhookconfiguration $webhook; done
	@oc delete scc multicloud-scc || true
	@oc delete clusterrole multicluster-mongodb
	@oc delete clusterrolebinding multicluster-mongodb
	@oc delete sub etcd-singlenamespace-alpha-community-operators-openshift-marketplace
	@oc delete sub multicluster-operators-subscription-alpha-community-operators-openshift-marketplace
	@oc delete sub hive-operator-alpha-community-operators-openshift-marketplace
	@oc delete sub multiclusterhub-operator

resubscribe: unsubscribe subscribe


deps:
	./cicd-scripts/install-dependencies.sh
	go mod tidy
