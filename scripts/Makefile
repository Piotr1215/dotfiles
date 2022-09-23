.PHONY : all install_kind_linux install_kind_mac create_kind_cluster setup_aws cleanup install_crossplane_cli

default: all

KIND_VERSION := $(shell kind --version 2>/dev/null)

install_kind_linux : 
ifdef KIND_VERSION
	@echo "Found version $(KIND_VERSION)"
else
	@curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.10.0/kind-linux-amd64
	@chmod +x ./kind
	@mv ./kind /bin/kind
endif

install_kind_mac : 
ifdef KIND_VERSION
	@echo "Found version $(KIND_VERSION)"
else
	@brew install kind
endif

create_kind_cluster :
	@echo "Creating kind cluster"
	@kind create cluster --name crossplane-cluster 
	@kind get kubeconfig --name crossplane-cluster
	@kubectl config set-context kind-crossplane-cluster 

create_kind_cluster_with_ingress :
	@echo "Creating kind cluster"
	@kind create cluster --name crossplane-cluster --config=kind-config.yaml
	@kind get kubeconfig --name crossplane-cluster
	@kubectl config set-context kind-crossplane-cluster 
	@kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

install_crossplane : 
	@echo "Installing crossplane"
	@kubectl create namespace crossplane-system
	@helm repo add crossplane-stable https://charts.crossplane.io/stable
	@helm repo upate
	@helm install crossplane --namespace crossplane-system crossplane-stable/crossplane
	@kubectl wait deployment.apps/crossplane --namespace crossplane-system --for condition=AVAILABLE=True --timeout 1m

install_crossplane_revisions : 
	@echo "Installing crossplane"
	@kubectl create namespace crossplane-system
	@helm repo add crossplane-stable https://charts.crossplane.io/stable
	@helm repo upate
	@helm install crossplane --namespace crossplane-system crossplane-stable/crossplane --set args='{--enable-composition-revisions}'
	@kubectl wait deployment.apps/crossplane --namespace crossplane-system --for condition=AVAILABLE=True --timeout 1m

CROSSPLANE_CLI := $(shell kubectl crossplane --version 2>/dev/null)

install_crossplane_cli :
ifdef CROSSPLANE_CLI
	@echo "Crssplane CLI already installed"
else
	@curl -sL https://raw.githubusercontent.com/crossplane/crossplane/release-1.5/install.sh | sh
endif

setup_aws :
	@echo "Setting up AWS provider"
	@kubectl apply -f aws-provider.yaml
	@kubectl wait -f aws-provider.yaml --for condition=HEALTHY=True --timeout 1m
	./generate-aws-secret.sh
	@kubectl create secret generic aws-creds -n crossplane-system --from-file=creds=./creds.conf
	@kubectl apply -f aws-provider-config.yaml 
	@rm creds.conf

setup_azure :
	@echo "Setting up Azure provider"
	@kubectl apply -f azure-provider.yaml
	@kubectl wait -f azure-provider.yaml --for condition=HEALTHY=True --timeout 1m
	./generate-azure-secret.sh
	sleep 3
	@kubectl apply -f azure-provider-config.yaml
	rm azure-provider-config.yaml

setup_gcp :
	@echo "Setting up GCP provider"
	@kubectl apply -f gcp-provider.yaml
	@kubectl wait -f gcp-provider.yaml --for condition=HEALTHY=True --timeout 1m
	./generate-gcp-secret.sh
	sleep 3
	@kubectl apply -f gcp-provider-config.yaml 
	@rm gcp-provider-config.yaml

setup_k8s :
	@echo "Setting up Kubernetes provider for local cluster"
	@kubectl apply -f ./k8s-applications/kubernetes-provider-kind.yaml
	@kubectl wait provider.pkg.crossplane.io/crossplane-provider-kubernetes --for condition=HEALTHY=True --timeout 1m
	@echo "Provider Kubernetes configured"

setup_multi :
	@echo "Setting up multi k8s reference implementation"
	@kubectl crossplane install configuration registry.upbound.io/upbound/platform-ref-multi-k8s:v0.0.8
	@kubectl wait configuration.pkg.crossplane.io/upbound-platform-ref-multi-k8s --for condition=HEALTHY=True --timeout 1m
	./generate-aws-secret.sh
	@kubectl create secret generic aws-creds -n crossplane-system --from-file=creds=./creds.conf
	@kubectl apply -f aws-provider-config.yaml 
	@rm creds.conf

setup_kyverno :
	@echo "Setting up Kyverno"
	@kubectl apply -f https://raw.githubusercontent.com/kyverno/kyverno/main/config/release/install.yaml
	@kubectl --namespace kyverno \
    rollout status \
    deployment kyverno

setup_helm :
	@echo "Setting up Helm Provider"
	@kubectl apply -f ./gitops/helm-provider.yaml
	@kubectl wait -f ./gitops/helm-provider.yaml --for condition=HEALTHY=True --timeout 1m
	@kubectl apply -f ./gitops/helm-provider-config.yaml
	./elevate-helm-priviledges.sh

cleanup :
	@kind delete clusters crossplane-cluster

wsl : install_kind_linux create_kind_cluster install_crossplane install_crossplane_cli setup_aws

all : install_kind_mac create_kind_cluster install_crossplane install_crossplane_cli setup_aws

all_ingress : install_kind_mac create_kind_cluster_with_ingress install_crossplane install_crossplane_cli setup_aws

gcp : install_kind_mac create_kind_cluster install_crossplane install_crossplane_cli setup_gcp

gitops : install_kind_mac create_kind_cluster install_crossplane install_crossplane_cli setup_aws setup_helm

azure : install_kind_mac create_kind_cluster install_crossplane install_crossplane_cli setup_azure

demo : install_kind_linux create_kind_cluster_with_ingress install_crossplane install_crossplane_cli setup_aws setup_azure setup_k8s setup_kyverno

kyverno : install_kind_mac create_kind_cluster_with_ingress install_crossplane install_crossplane_cli setup_kyverno

no_provider : install_kind_mac create_kind_cluster_with_ingress install_crossplane install_crossplane_cli

empty : install_kind_mac create_kind_cluster 

revisions : install_kind_mac create_kind_cluster install_crossplane_revisions install_crossplane_cli setup_aws

multi_k8s : all setup_multi

local_k8s : install_kind_mac create_kind_cluster_with_ingress install_crossplane install_crossplane_cli setup_k8s
