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
