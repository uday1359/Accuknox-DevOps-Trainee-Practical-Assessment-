#!/bin/bash

echo "Starting DevOps Project..."

echo "Building Docker Image..."
docker build -t wisecow .

echo "Starting Minikube..."
minikube start

echo "Deploying to Kubernetes..."
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

echo "Getting Service URL..."
minikube service wisecow-service