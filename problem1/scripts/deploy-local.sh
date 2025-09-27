#!/usr/bin/env bash

set -e

echo "Deploying Wisecow to local Kubernetes cluster..."

sudo apt update
sudo apt install -y curl tar

if command -v helm >/dev/null 2>&1; then
    echo "✅ Helm is already installed. Skipping installation."
else
    echo "🚀 Helm not found. Installing..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    echo "✅ Helm installed successfully."
fi
helm version

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.crds.yaml

helm repo add jetstack https://charts.jetstack.io
helm repo update

if helm status cert-manager -n cert-manager >/dev/null 2>&1; then
    echo "✅ cert-manager already installed in namespace 'cert-manager'. Skipping installation."
else
    echo "🚀 Installing cert-manager..."
    helm install cert-manager jetstack/cert-manager \
      --namespace cert-manager \
      --create-namespace \
      --version v1.14.4
    echo "✅ cert-manager installed successfully."
fi

echo "Building Docker image..."
echo "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" | docker login ghcr.io -u uday1359 --password-stdin

docker build -t ghcr.io/uday1359/wisecow:latest .
docker push ghcr.io/uday1359/wisecow:latest


kubectl apply -f k8s/namespace.yaml
./scripts/create-tls-secret.sh
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/cert-manager/issuer.yaml
kubectl apply -f k8s/cert-manager/certificate.yaml
kubectl apply -f k8s/ingress.yaml

echo "Waiting for deployment to be ready..."
kubectl wait --for=condition=ready pod -l app=wisecow -n wisecow --timeout=380s

echo "Adding host entry for wisecow.local..."
if ! grep -q "wisecow.local" /etc/hosts; then
    echo "127.0.0.1 wisecow.local" | sudo tee -a /etc/hosts
fi

MINIKUBE_IP=$(minikube ip)
echo "Minikube IP: $MINIKUBE_IP"

echo "Deployment completed successfully!"
echo "Application URLs:"
echo "- HTTPS: https://wisecow.local"
echo "- HTTP via port-forward: kubectl port-forward -n wisecow service/wisecow-service 8080:80"
