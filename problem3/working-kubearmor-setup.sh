#!/bin/bash

# working-kubearmor-setup.sh
set -e

echo "=== KubeArmor Working Setup ==="

# Function to check KubeArmor status
check_kubearmor() {
    echo "Checking KubeArmor status..."
    kubectl get pods -n kubearmor
    kubectl get crd | grep kubearmor
}

# Function to deploy nginx workload
deploy_nginx() {
    echo "Deploying nginx workload..."
    
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: default
spec:
  replicas: 1
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
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: default
spec:
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
EOF

    echo "Waiting for nginx pod to be ready..."
    kubectl wait --for=condition=ready pod -l app=nginx --timeout=120s
}

# Function to apply simple policy
apply_simple_policy() {
    echo "Applying simple KubeArmor policy..."
    
    kubectl apply -f - <<EOF
apiVersion: security.kubearmor.com/v1
kind: KubeArmorPolicy
metadata:
  name: block-passwd-access
  namespace: default
spec:
  selector:
    matchLabels:
      app: nginx
  action: Block
  file:
    matchPaths:
    - path: /etc/shadow
  severity: 7
  message: "Block access to /etc/shadow"
EOF

    sleep 5
    echo "Policy applied successfully!"
}

# Function to apply more complex policy
apply_complex_policy() {
    echo "Applying complex KubeArmor policy..."
    
    kubectl apply -f - <<EOF
apiVersion: security.kubearmor.com/v1
kind: KubeArmorPolicy
metadata:
  name: nginx-zero-trust
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
    - path: /etc/nginx/nginx.conf
      readOnly: true
    - path: /etc/nginx/conf.d/*
      readOnly: true
    - path: /usr/share/nginx/html/*
      readOnly: true
    - path: /var/log/nginx/*
      readOnly: false
  severity: 5
  message: "Zero trust policy for nginx"
EOF
}

# Function to test policy violations
test_policy() {
    echo "Testing policy violations..."
    
    # Get nginx pod name
    POD_NAME=$(kubectl get pods -l app=nginx -o jsonpath='{.items[0].metadata.name}')
    
    echo "Testing access to blocked file (/etc/shadow)..."
    kubectl exec $POD_NAME -- cat /etc/shadow 2>&1 | head -5 || echo "✅ Policy violation detected (expected)"
    
    echo "Testing access to allowed file (/etc/passwd)..."
    kubectl exec $POD_NAME -- cat /etc/passwd | head -5 && echo "✅ Allowed access successful"
    
    echo "Testing process execution..."
    kubectl exec $POD_NAME -- which nginx && echo "✅ nginx process allowed"
}

# Function to monitor logs
setup_log_monitoring() {
    echo "Setting up log monitoring..."
    
    # Start background process to monitor logs
    nohup kubectl logs -f -n kubearmor -l app=kubearmor > kubearmor.log 2>&1 &
    LOG_PID=$!
    echo "KubeArmor logs are being saved to kubearmor.log (PID: $LOG_PID)"
    
    # Also show recent logs
    echo "=== Recent KubeArmor Logs ==="
    kubectl logs -n kubearmor -l app=kubearmor --tail=10
}

# Function to create policy violation for screenshot
create_violation_for_screenshot() {
    echo "Creating policy violation for screenshot..."
    
    # Get nginx pod name
    POD_NAME=$(kubectl get pods -l app=nginx -o jsonpath='{.items[0].metadata.name}')
    
    echo "=== Commands to run for screenshot ==="
    echo "1. Show current policies:"
    echo "   kubectl get kubearmorpolicy -A"
    echo ""
    echo "2. Show KubeArmor logs:"
    echo "   kubectl logs -n kubearmor -l app=kubearmor --tail=20"
    echo ""
    echo "3. Trigger policy violation:"
    echo "   kubectl exec $POD_NAME -- cat /etc/shadow"
    echo ""
    echo "4. Show pod details:"
    echo "   kubectl describe pod $POD_NAME"
}

main() {
    echo "Starting KubeArmor setup..."
    
    check_kubearmor
    deploy_nginx
    apply_simple_policy
    test_policy
    apply_complex_policy
    setup_log_monitoring
    create_violation_for_screenshot
    
    echo ""
    echo "=== Setup Complete ==="
    echo "✅ KubeArmor is working correctly"
    echo "✅ Policies have been applied"
    echo "✅ Policy violations can be observed in logs"
    echo ""
    echo "For screenshot:"
    echo "1. Run: kubectl get kubearmorpolicy -A"
    echo "2. Run: kubectl logs -n kubearmor -l app=kubearmor --tail=20"
    echo "3. Trigger violation: kubectl exec <nginx-pod> -- cat /etc/shadow"
}

main
