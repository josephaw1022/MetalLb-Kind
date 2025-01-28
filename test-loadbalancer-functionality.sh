#!/bin/bash

# Define namespace
NAMESPACE="nginx-example"
ISTIO_GATEWAY="local-env-test-gateway"
DOMAIN="nginx.local-env.test"

# Create namespace with Istio injection label
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "Creating namespace $NAMESPACE with Istio injection enabled..."
    kubectl create namespace "$NAMESPACE"
    kubectl label namespace "$NAMESPACE" istio-injection=enabled
else
    echo "Namespace $NAMESPACE already exists. Ensuring Istio injection label is applied..."
    kubectl label namespace "$NAMESPACE" istio-injection=enabled --overwrite
fi

# Define Nginx Deployment YAML
NGINX_DEPLOYMENT=$(cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: $NAMESPACE
  labels:
    app: nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.21.6
        ports:
        - containerPort: 80
EOF
)

# Define Nginx ClusterIP Service YAML
NGINX_SERVICE=$(cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: $NAMESPACE
spec:
  selector:
    app: nginx
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: ClusterIP
EOF
)

# Define VirtualService YAML
NGINX_VIRTUAL_SERVICE=$(cat <<EOF
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: nginx-virtualservice
  namespace: $NAMESPACE
spec:
  hosts:
  - nginx.local-env.test
  gateways:
  - istio-ingress/$ISTIO_GATEWAY
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: nginx-service.$NAMESPACE.svc.cluster.local
        port:
          number: 80
EOF
)

# Apply Nginx Deployment
if ! kubectl get deployment nginx -n "$NAMESPACE" &>/dev/null; then
    echo "Creating Nginx deployment in namespace $NAMESPACE..."
    echo "$NGINX_DEPLOYMENT" | kubectl apply -f -
else
    echo "Nginx deployment already exists in namespace $NAMESPACE. Skipping creation."
fi

# Apply Nginx Service
if ! kubectl get svc nginx-service -n "$NAMESPACE" &>/dev/null; then
    echo "Creating Nginx ClusterIP service in namespace $NAMESPACE..."
    echo "$NGINX_SERVICE" | kubectl apply -f -
else
    echo "Nginx service already exists in namespace $NAMESPACE. Skipping creation."
fi

# Apply VirtualService
if ! kubectl get virtualservice nginx-virtualservice -n "$NAMESPACE" &>/dev/null; then
    echo "Creating Nginx VirtualService in namespace $NAMESPACE..."
    echo "$NGINX_VIRTUAL_SERVICE" | kubectl apply -f -
else
    echo "Nginx VirtualService already exists in namespace $NAMESPACE. Skipping creation."
fi

# Wait for Nginx pods to be ready
echo "Waiting for Nginx pods to be ready..."
kubectl wait --for=condition=ready pod -l app=nginx --timeout=60s -n "$NAMESPACE"
kubectl get pods -l app=nginx -n "$NAMESPACE"

echo "Setup complete. You can now access Nginx at: http://$DOMAIN"
