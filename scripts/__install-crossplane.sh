!#/usr/bin/env bash

set eo pipefail

echo "Installing crossplane"
kubectl create namespace crossplane-system
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo upate
helm install crossplane --namespace crossplane-system crossplane-stable/crossplane
kubectl wait deployment.apps/crossplane --namespace crossplane-system --for condition=AVAILABLE=True --timeout 1m


