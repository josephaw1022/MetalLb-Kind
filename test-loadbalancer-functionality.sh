#!/bin/bash

# Define namespace
NAMESPACE="nginx-example"

# Create namespace if it doesn't exist
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "Creating namespace $NAMESPACE..."
    kubectl create namespace "$NAMESPACE"
else
    echo "Namespace $NAMESPACE already exists. Skipping creation."
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

# Define Nginx LoadBalancer Service YAML
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
  type: LoadBalancer
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
    echo "Creating Nginx LoadBalancer service in namespace $NAMESPACE..."
    echo "$NGINX_SERVICE" | kubectl apply -f -
else
    echo "Nginx LoadBalancer service already exists in namespace $NAMESPACE. Skipping creation."
fi

# Wait for Nginx pods to be ready
echo "Waiting for Nginx pods to be ready..."
kubectl wait --for=condition=ready pod -l app=nginx --timeout=60s -n "$NAMESPACE"
kubectl get pods -l app=nginx -n "$NAMESPACE"

# Get Nginx LoadBalancer service details
NGINX_LB_IP=$(kubectl get svc nginx-service -n "$NAMESPACE" -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -n "$NGINX_LB_IP" ]; then
    echo "Nginx LoadBalancer is available at: http://$NGINX_LB_IP"
else
    echo "Nginx LoadBalancer IP is not available yet. Service might still be initializing."
fi
