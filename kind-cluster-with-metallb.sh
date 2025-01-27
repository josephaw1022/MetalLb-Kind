#!/bin/bash

# Create Kind network if needed
docker network create kind || true

# Delete Kind cluster
kind delete cluster || true

# Wait for the cluster to clean up
sleep 2

# Create Kind cluster
# Uncomment the line below if you want to create the cluster
kind create cluster --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
EOF


# Calculate MetalLB IP range
echo "Using Docker..."
KIND_NET_CIDR=$(docker network inspect kind -f '{{(index .IPAM.Config 0).Subnet}}')
KIND_NET_BASE=$(echo "${KIND_NET_CIDR}" | awk -F'.' '{print $1"."$2"."$3}')
METALLB_IP_START="${KIND_NET_BASE}.200" # Starting IP
METALLB_IP_END="${KIND_NET_BASE}.254"   # Ending IP

echo "kind cidr: ${KIND_NET_CIDR}"
echo "kind network base: ${KIND_NET_BASE}"
echo "MetalLB IP range: ${METALLB_IP_START}-${METALLB_IP_END}"

# Calculate MetalLB IP range
METALLB_IP_RANGE="${METALLB_IP_START}-${METALLB_IP_END}"

# Echo the MetalLB IP range
echo "MetalLB IP range: ${METALLB_IP_RANGE}"

# Add Helm repository for MetalLB
helm repo add metallb https://metallb.github.io/metallb

# Update Helm repositories
helm repo update

# Install MetalLB using Helm
helm install metallb metallb/metallb \
  --namespace metallb-system --create-namespace

sleep 80


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

