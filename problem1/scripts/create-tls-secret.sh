#!/bin/bash

# TLS certificate creation script

set -e

echo "Creating TLS certificates for Wisecow..."

# Create self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout wisecow.key \
    -out wisecow.crt \
    -subj "/CN=wisecow.local/O=wisecow"

# Create Kubernetes TLS secret
kubectl create secret tls wisecow-tls \
    --cert=wisecow.crt \
    --key=wisecow.key \
    --namespace=wisecow

echo "TLS secret created successfully!"
echo "Certificate files: wisecow.crt, wisecow.key"
