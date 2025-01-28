#!/bin/bash

set -e


# Create a folder to store certificate files if it doesn't exist
if [ ! -d .ssl ]; then
  echo "Creating folder to store certificate files..."
  mkdir -p .ssl
else
  echo "Certificate folder already exists. Skipping creation."
fi

# Generate an RSA key if it doesn't exist
if [ ! -f .ssl/root-ca-key.pem ]; then
  echo "Generating RSA key for root CA..."
  openssl genrsa -out .ssl/root-ca-key.pem 2048
else
  echo "RSA key for root CA already exists. Skipping generation."
fi

# Generate a root certificate if it doesn't exist
if [ ! -f .ssl/root-ca.pem ]; then
  echo "Generating root CA certificate..."
  openssl req -x509 -new -nodes -key .ssl/root-ca-key.pem \
    -days 3650 -sha256 -out .ssl/root-ca.pem -subj "/CN=kube-ca"
else
  echo "Root CA certificate already exists. Skipping generation."
fi

# Add SSL certificate to the trusted certificates directory on Fedora
echo "Adding root CA to the trusted certificates directory..."
sudo cp .ssl/root-ca.pem /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust extract
echo "Root CA added to trusted certificates."


# Create Kind network if needed
docker network create kind || true

# Delete Kind cluster if it exists
kind delete cluster || true

# Wait for the cluster to clean up
sleep 2

# Create Kind cluster with three worker nodes
echo "Creating Kind cluster with three worker nodes..."
kind create cluster --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
- role: worker
EOF

# Setup Helm Repos and Install Helm Charts
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add metallb https://metallb.github.io/metallb
helm repo update

# Install MetalLB
helm upgrade --wait --install metallb metallb/metallb --namespace metallb-system --create-namespace

# Install Prometheus Stack
helm upgrade --wait --install kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace

# Install cert-manager
helm upgrade --wait --install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.16.2 --set crds.enabled=true

# Wait for MetalLB to stabilize
echo "Waiting for MetalLB to stabilize..."

sleep 80

# Calculate MetalLB IP range
KIND_NET_CIDR=$(docker network inspect kind -f '{{(index .IPAM.Config 0).Subnet}}')
KIND_NET_BASE=$(echo "${KIND_NET_CIDR}" | awk -F'.' '{print $1"."$2"."$3}')
METALLB_IP_START="${KIND_NET_BASE}.200"
METALLB_IP_END="${KIND_NET_BASE}.254"
METALLB_IP_RANGE="${METALLB_IP_START}-${METALLB_IP_END}"

# Apply MetalLB configuration
kubectl apply -f - <<EOF
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

sleep 10

# Install Istio
helm upgrade --install istio-base istio/base -n istio-system --create-namespace --wait
helm upgrade --install istiod istio/istiod -n istio-system --wait
helm upgrade --install istio-ingress istio/gateway -n istio-ingress --create-namespace

# Create cert-manager ClusterIssuer (Self-Signed)
echo "Creating cert-manager self-signed ClusterIssuer..."
kubectl apply -n cert-manager -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: self-signed-issuer
spec:
  selfSigned: {}
EOF

# Create cert-manager ClusterIssuer (CA-Based)
echo "Creating cert-manager CA-based ClusterIssuer..."
kubectl create secret tls -n cert-manager root-ca --cert=".ssl/root-ca.pem" --key=".ssl/root-ca-key.pem"
kubectl apply -n cert-manager -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ca-issuer
spec:
  ca:
    secretName: root-ca
EOF

# Define the custom domain
CUSTOM_DOMAIN="local-env.test"
GATEWAY_NAME="local-env-test-gateway"

# Create a certificate for the Istio Gateway
echo "Creating certificate for the Istio Gateway..."
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${CUSTOM_DOMAIN}-cert
  namespace: istio-ingress
spec:
  secretName: ${CUSTOM_DOMAIN}-tls-secret
  commonName: "*.${CUSTOM_DOMAIN}"
  dnsNames:
    - "${CUSTOM_DOMAIN}"
    - "*.${CUSTOM_DOMAIN}"
  issuerRef:
    name: self-signed-issuer
    kind: ClusterIssuer
EOF


# Create a certificate for the Istio Gateway using the CA issuer
echo "Creating certificate for the Istio Gateway..."
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${CUSTOM_DOMAIN}-cert-ca
  namespace: istio-ingress
spec:
  secretName: ${CUSTOM_DOMAIN}-tls-secret-ca
  commonName: "*.${CUSTOM_DOMAIN}"
  dnsNames:
    - "${CUSTOM_DOMAIN}"
    - "*.${CUSTOM_DOMAIN}"
  issuerRef:
    name: ca-issuer
    kind: ClusterIssuer
EOF


# Create Istio Gateway
echo "Creating Istio Gateway..."
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: ${GATEWAY_NAME}
  namespace: istio-ingress
spec:
  selector:
    istio: ingress
  servers:
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - "*.${CUSTOM_DOMAIN}"
      tls:
        httpsRedirect: true
    - port:
        number: 443
        name: https
        protocol: HTTPS
      hosts:
        - "*.${CUSTOM_DOMAIN}"
      tls:
        mode: SIMPLE
        credentialName: ${CUSTOM_DOMAIN}-tls-secret-ca
EOF

echo "Setup complete. Your Kind cluster is configured with MetalLB, cert-manager (self-signed issuer), and Istio for ${CUSTOM_DOMAIN}."
