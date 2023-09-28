#!/bin/zsh

# Header info
echo "-------------------"
echo "System Information:"
echo "-------------------"

# Get general system information
echo "OS Details:"
uname -a
echo ""

# Get kind version
echo "----------------"
echo "Kind Version:"
echo "----------------"
kind version
echo ""

# Get kubectl version
echo "-------------------"
echo "Kubectl Version:"
echo "-------------------"
kubectl version
kubectl get --raw /version
echo ""

# Get Crossplane version
echo "--------------------"
echo "Crossplane Version:"
echo "--------------------"
# Check if crossplane is running in kind cluster
if kubectl get pods -n crossplane-system &>/dev/null; then
	kubectl get deployment crossplane -n crossplane-system -o=jsonpath='{.spec.template.spec.containers[0].image}'
else
	echo "Crossplane is not installed or not running in the 'crossplane-system' namespace."
fi
echo ""
echo ""

# Get Kubernetes Node and Pod Information
echo "----------------------------------------"
echo "Kubernetes Node and Pod Information:"
echo "----------------------------------------"
if kubectl cluster-info &>/dev/null; then
	echo "Node Information:"
	kubectl get nodes
	echo ""
	echo "Pod Information:"
	echo ""
	kubectl get pods --all-namespaces
	{
		echo -e "\nKubernetes Status:\n" && kubectl get --raw '/healthz?verbose'
		echo && kubectl get nodes
		echo && kubectl cluster-info
		echo && kubectl version
		echo
	} | grep -z 'Ready\| ok\|passed\|running'

else
	echo "Kubernetes cluster is not reachable."
fi
echo ""
