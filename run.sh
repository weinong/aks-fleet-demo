#!/bin/bash

# exit upon error and print the command
set -ex

# USER is your Azure user email address
USER=
SUBSCRIPTION=
RESOURCEGROUP=aks-fleet
HUB_LOCATION=eastus

# check if kubelogin executable is available
# I'd like to use kubelogin to streamline the login process
if ! command -v kubelogin &> /dev/null
then
	echo "kubelogin could not be found"
	echo "Please install kubelogin from https://azure.github.io/kubelogin/install.html"
	exit
fi

az account set --subscription ${SUBSCRIPTION}

az group create -n ${RESOURCEGROUP} -l ${HUB_LOCATION}

az role assignment create \
	--scope /subscriptions/${SUBSCRIPTION}/resourceGroups/${RESOURCEGROUP} \
	--role "Azure Kubernetes Fleet Manager RBAC Cluster Admin" \
	--assignee ${USER}

az role assignment create \
	--scope /subscriptions/${SUBSCRIPTION}/resourceGroups/${RESOURCEGROUP} \
	--role "Azure Kubernetes Service RBAC Cluster Admin" \
	--assignee ${USER}

az fleet create -n hub -g ${RESOURCEGROUP} -l ${HUB_LOCATION} --enable-hub

az fleet get-credentials -g ${RESOURCEGROUP} -n hub --overwrite-existing

kubelogin convert-kubeconfig -l azurecli --context hub

# create 3 AKS clusters
for i in {1..3}; do
  az aks create -g ${RESOURCEGROUP} -n aks${i} \
	--location westus3 \
	--enable-azure-rbac \
	--enable-aad \
	--enable-app-routing \
	--auto-upgrade-channel node-image \
	--enable-asm \
	--enable-managed-identity \
	--enable-oidc-issuer \
	--enable-workload-identity \
	--network-dataplane cilium \
	--network-plugin azure \
	--network-plugin-mode overlay \
	--network-policy cilium \
	--node-count 1 \
	--node-os-upgrade-channel NodeImage \
	--node-vm-size Standard_D2s_v3 \
	--os-sku AzureLinux \
	--no-ssh-key \
	--tier standard

	az aks get-credentials -g ${RESOURCEGROUP} -n aks${i} --overwrite-existing

	kubelogin convert-kubeconfig -l azurecli --context aks${i}
done

# join the first two clusters to fleet
for i in {1..2}; do
	az fleet member create -g ${RESOURCEGROUP} -f hub -n aks${i} \
	--member-cluster-id \
	/subscriptions/${SUBSCRIPTION}/resourcegroups/${RESOURCEGROUP}/providers/Microsoft.ContainerService/managedClusters/aks${i} \
	--update-group group${i}
done

# az fleet member create -g ${RESOURCEGROUP} -f hub -n aks3 --member-cluster-id /subscriptions/${SUBSCRIPTION}/resourcegroups/aks-fleet/providers/Microsoft.ContainerService/managedClusters/aks3 --update-group group3

kubectl config use-context hub

# apply cluster resource placement to mirror fluent-bit namespace to all members
kubectl apply -f - <<EOF
apiVersion: placement.kubernetes-fleet.io/v1beta1
kind: ClusterResourcePlacement
metadata:
  name: crp
spec:
  resourceSelectors:
    - group: ""
      kind: Namespace
      version: v1          
      name: fluent-bit
  policy:
    placementType: PickAll
EOF

helm repo add fluent https://fluent.github.io/helm-charts

helm repo update

helm install -n fluent-bit --create-namespace fluent-bit fluent/fluent-bit

sleep 180

kubectl describe clusterresourceplacement crp

# verify fluent-bit is mirrored to aks1
kubectl config use-context aks1
kubectl -n fluent-bit get pods

# verify fluent-bit is mirrored to aks2
kubectl config use-context aks2
kubectl -n fluent-bit get pods

# join the last cluster to the fleet
az fleet member create -g ${RESOURCEGROUP} -f hub -n aks3 \
	--member-cluster-id \
	/subscriptions/${SUBSCRIPTION}/resourcegroups/aks-fleet/providers/Microsoft.ContainerService/managedClusters/aks3 \
	--update-group group3

sleep 30

kubectl config use-context aks3

# verify fluent-bit is mirrored to aks3
kubectl -n fluent-bit get pods

# only delete the environment when CLEANUP is set
if [ -n "${CLEANUP}" ]; then
	# deleting the cluster resource placement will result in fluent-bit being removed from all members
	kubectl config use-context hub
	kubectl delete clusterresourceplacement crp

	for i in {1..3}; do
		kubectl config use-context aks${i}
		kubectl -n fluent-bit get pods || true
	done

	# cleanup
	az group delete -n ${RESOURCEGROUP} -y --no-wait
fi
