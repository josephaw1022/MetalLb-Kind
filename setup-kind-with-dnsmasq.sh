# Add Helm repository for Cilium
helm repo add cilium https://helm.cilium.io

# Add Helm repository for MetalLB
helm repo add metallb https://metallb.github.io/metallb

# Add Helm repository for ingress-nginx
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

# Update all repositories to ensure you have the latest charts
helm repo update


# Stop all containers
echo "Stopping all containers..."
docker stop $(docker ps -q)

# Delete all containers
echo "Removing all containers..."
docker rm $(docker ps -aq)



# create kind network if needed
docker network create kind || true
# start registry proxies
# docker run -d --name proxy-docker-hub --restart=always --net=kind -e REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io registry:2 || true
# docker run -d --name proxy-quay --restart=always --net=kind -e REGISTRY_PROXY_REMOTEURL=https://quay.io registry:2 || true
# docker run -d --name proxy-gcr --restart=always --net=kind -e REGISTRY_PROXY_REMOTEURL=https://gcr.io registry:2 || true
# docker run -d --name proxy-k8s-gcr --restart=always --net=kind -e REGISTRY_PROXY_REMOTEURL=https://k8s.gcr.io registry:2 || true
# delete kind cluster
kind delete cluster || true

# wait 2 seconds
sleep 2


# Ensure kubeconfig is placed in the default location (~/.kube/config)
DEFAULT_KUBECONFIG="${HOME}/.kube/config"

# Check if the default kubeconfig exists and remove it
if [ -f "${DEFAULT_KUBECONFIG}" ]; then
    echo "Removing existing kubeconfig: ${DEFAULT_KUBECONFIG}"
    rm -f "${DEFAULT_KUBECONFIG}"
fi

# Save kubeconfig to the default location
kind get kubeconfig --name kind > "${DEFAULT_KUBECONFIG}"

# Set KUBECONFIG environment variable
export KUBECONFIG="${DEFAULT_KUBECONFIG}"

echo "Kubeconfig has been saved to: ${DEFAULT_KUBECONFIG}"
echo "KUBECONFIG environment variable set to: ${KUBECONFIG}"

sleep 2

# create kind cluster
kind create cluster  --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
  kubeProxyMode: none
nodes:
- role: control-plane
- role: worker
EOF


# install cilium
helm upgrade --install --namespace kube-system --repo https://helm.cilium.io cilium cilium --values - <<EOF
kubeProxyReplacement: true
k8sServiceHost: kind-external-load-balancer
k8sServicePort: 6443
hostServices:
  enabled: true
externalIPs:
  enabled: true
nodePort:
  enabled: true
hostPort:
  enabled: true
image:
  pullPolicy: IfNotPresent
ipam:
  mode: kubernetes
hubble:
  enabled: true
  relay:
    enabled: true
  ui:
    enabled: true
    ingress:
      enabled: true
      annotations:
        kubernetes.io/ingress.class: nginx
      hosts:
        - hubble-ui.kind.cluster
EOF

# install metallb
if command -v podman &> /dev/null; then
    # Podman is installed
    echo "Using Podman..."
    KIND_NET_CIDR=$(podman network inspect kind --format '{{range .Subnets}}{{.Subnet}}{{end}}')
    METALLB_IP_START=$(echo "${KIND_NET_CIDR}" | sed 's@0.0/24@255.200@')
    METALLB_IP_END=$(echo "${KIND_NET_CIDR}" | sed 's@0.0/24@255.250@')
else
    # Fall back to Docker
    echo "Using Docker..."
    KIND_NET_CIDR=$(docker network inspect kind -f '{{(index .IPAM.Config 0).Subnet}}')
    METALLB_IP_START=$(echo "${KIND_NET_CIDR}" | sed 's@0.0/16@255.200@')
    METALLB_IP_END=$(echo "${KIND_NET_CIDR}" | sed 's@0.0/16@255.250@')
fi

# Calculate MetalLB IP range
METALLB_IP_RANGE="${METALLB_IP_START}-${METALLB_IP_END}"


# Add Helm repository for MetalLB
helm repo add metallb https://metallb.github.io/metallb

# Update Helm repositories
helm repo update

# Install MetalLB using Helm
helm install metallb metallb/metallb \
    --namespace metallb-system --create-namespace

# Wait for MetalLB components to become ready
echo "Waiting for MetalLB components to become ready..."

exit 0
kubectl wait --namespace metallb-system --for=condition=Available deployment/metallb-controller --timeout=120s
kubectl wait --namespace metallb-system --for=condition=Available deployment/metallb-webhook --timeout=120s

# Apply MetalLB configuration using a ConfigMap
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  namespace: metallb-system
  name: default-address-pool
spec:
  addresses:
  - ${METALLB_IP_RANGE}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  namespace: metallb-system
  name: default
EOF


# wait for pods to be ready
kubectl wait -A --for=condition=ready pod --field-selector=status.phase!=Succeeded --timeout=20m
# install ingress-nginx
helm upgrade --install --namespace ingress-nginx --create-namespace --repo https://kubernetes.github.io/ingress-nginx ingress-nginx ingress-nginx --values - <<EOF
defaultBackend:
  enabled: true
EOF
# wait for pods to be ready
kubectl wait -A --for=condition=ready pod --field-selector=status.phase!=Succeeded --timeout=15m
# retrieve local load balancer IP address
LB_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
# point kind.cluster domain (and subdomains) to our load balancer
echo "address=/kind.cluster/$LB_IP" | sudo tee /etc/dnsmasq.d/kind.k8s.conf
# restart dnsmasq
sudo systemctl restart dnsmasq