#!/bin/bash

# quick-fix.sh

# Delete the problematic policy if it exists
kubectl delete kubearmorpolicy zero-trust-workload-policy -n default --ignore-not-found=true

# Apply the corrected policy
kubectl apply -f - <<EOF
apiVersion: security.kubearmor.com/v1
kind: KubeArmorPolicy
metadata:
  name: zero-trust-nginx
  namespace: default
spec:
  selector:
    matchLabels:
      app: nginx
  action: Allow
  process:
    matchPaths:
    - path: /usr/sbin/nginx
  file:
    matchPaths:
    - path: /etc/nginx/*
      readOnly: true
    - path: /var/log/nginx/*
      readOnly: false
  severity: 5
EOF

echo "Policy applied successfully!"
kubectl get kubearmorpolicy -A
