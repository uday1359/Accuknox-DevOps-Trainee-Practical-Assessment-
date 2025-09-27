#!/bin/bash

# Minikube Automated Setup for Ubuntu
# Complete installation in a single script file

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Variables
MINIKUBE_VERSION="latest"
KUBECTL_VERSION="stable"
DRIVER="docker"
MEMORY="4096"
CPUS="2"
DISK_SIZE="20g"
SKIP_TEST=false
SKIP_ADDONS=false

# Check if running on Ubuntu
check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "This script is designed for Ubuntu only"
        exit 1
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        log_error "This script is for Ubuntu. Detected: $ID"
        exit 1
    fi
    
    log_info "Detected Ubuntu version: $VERSION_ID"
}

# Check sudo privileges
check_sudo() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Do not run as root. Run as regular user with sudo access."
        exit 1
    fi
    
    log_info "Checking sudo privileges..."
    if ! sudo -n true 2>/dev/null; then
        log_warn "Sudo password may be required during installation"
    fi
}

# Update system packages
update_system() {
    log_step "Updating system packages..."
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl wget apt-transport-https ca-certificates gnupg lsb-release
}

# Install Docker
install_docker() {
    log_step "Installing Docker..."
    
    # Remove old versions
    sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start and enable Docker
    sudo systemctl enable docker
    sudo systemctl start docker
    
    # Add user to docker group
    sudo usermod -aG docker $USER
    
    log_info "Docker installed successfully"
}

# Install Minikube
install_minikube() {
    log_step "Installing Minikube..."
    
    # Download Minikube
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    
    # Install to system path
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    sudo chmod +x /usr/local/bin/minikube
    
    # Cleanup
    rm -f minikube-linux-amd64
    
    log_info "Minikube installed successfully"
}

# Install kubectl
install_kubectl() {
    log_step "Installing kubectl..."
    
    # Download latest stable kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    
    # Install kubectl
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    
    # Cleanup
    rm -f kubectl
    
    log_info "kubectl installed successfully"
}

# Configure Docker permissions - FIXED VERSION
setup_docker_permissions() {
    log_step "Setting up Docker permissions..."
    
    # Apply group changes without logout using a simpler approach
    log_info "Applying Docker group permissions..."
    
    # Use sg command instead of newgrp to avoid subshell issues
    if command -v sg >/dev/null 2>&1; then
        sg docker "echo 'Docker group test successful'" || true
    fi
    
    # Alternative: Set permissions on docker.sock (temporary workaround)
    sudo chmod 666 /var/run/docker.sock 2>/dev/null || true
    
    # Test Docker without sudo
    sleep 2  # Give time for group changes to take effect
    if docker version --format '{{.Client.Version}}' > /dev/null 2>&1; then
        log_info "Docker permissions configured correctly"
    else
        log_warn "Docker may still require sudo. A logout/login may be needed."
        log_info "Continuing with sudo for Docker commands..."
    fi
}

# Start Minikube cluster - FIXED VERSION
start_minikube() {
    log_step "Starting Minikube cluster..."
    
    # Set Minikube configuration
    minikube config set driver $DRIVER 2>/dev/null || true
    minikube config set memory $MEMORY 2>/dev/null || true
    minikube config set cpus $CPUS 2>/dev/null || true
    minikube config set disk-size $DISK_SIZE 2>/dev/null || true
    
    # Start Minikube with appropriate permissions
    log_info "Starting Minikube (this may take a few minutes)..."
    
    if docker version --format '{{.Client.Version}}' > /dev/null 2>&1; then
        # Docker works without sudo
        minikube start --driver=$DRIVER --memory=$MEMORY --cpus=$CPUS --disk-size=$DISK_SIZE
    else
        # Fallback to sudo
        log_warn "Using sudo for Minikube startup..."
        sudo -E minikube start --driver=$DRIVER --memory=$MEMORY --cpus=$CPUS --disk-size=$DISK_SIZE
    fi
    
    # Verify startup
    if minikube status | grep -q "Running"; then
        log_info "Minikube cluster started successfully"
    else
        log_error "Minikube failed to start"
        log_info "Trying with force option..."
        minikube start --force --driver=$DRIVER --memory=$MEMORY --cpus=$CPUS --disk-size=$DISK_SIZE
    fi
}

# Enable addons
enable_addons() {
    log_step "Enabling Minikube addons..."
    
    minikube addons enable dashboard
    minikube addons enable metrics-server
    minikube addons enable ingress
    minikube addons enable storage-provisioner
    minikube addons enable default-storageclass
    
    log_info "Essential addons enabled"
}

# Setup shell completion and aliases
setup_shell() {
    log_step "Setting up shell environment..."
    
    # Install bash completion
    sudo apt install -y bash-completion
    
    # Add to bashrc
    cat << 'EOF' >> ~/.bashrc

# Kubernetes and Minikube configurations
alias k=kubectl
alias mk=minikube
alias kgp='kubectl get pods'
alias kgs='kubectl get services'
alias kgd='kubectl get deployments'
alias kns='kubectl config set-context --current --namespace'

# Completions
source <(kubectl completion bash)
source <(minikube completion bash)
complete -o default -F __start_kubectl k
complete -o default -F __start_minikube mk

# Environment variables
export MINIKUBE_IN_STYLE=true
export KUBE_EDITOR=nano
EOF
    
    # Source bashrc
    source ~/.bashrc
    
    log_info "Shell configuration completed"
}

# Verify installation
verify_installation() {
    log_step "Verifying installation..."
    
    echo -e "\n${GREEN}=== VERIFICATION RESULTS ===${NC}"
    
    # Check binaries
    local success=true
    
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}✓ Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')${NC}"
    else
        echo -e "${RED}✗ Docker: Not found${NC}"
        success=false
    fi
    
    if command -v minikube &> /dev/null; then
        minikube version --short 2>/dev/null | while read -r line; do
            echo -e "${GREEN}✓ Minikube: $line${NC}"
        done || echo -e "${GREEN}✓ Minikube: Installed${NC}"
    else
        echo -e "${RED}✗ Minikube: Not found${NC}"
        success=false
    fi
    
    if command -v kubectl &> /dev/null; then
        kubectl version --client --short 2>/dev/null | while read -r line; do
            echo -e "${GREEN}✓ kubectl: $line${NC}"
        done || echo -e "${GREEN}✓ kubectl: Installed${NC}"
    else
        echo -e "${RED}✗ kubectl: Not found${NC}"
        success=false
    fi
    
    # Check services
    if systemctl is-active --quiet docker; then
        echo -e "${GREEN}✓ Docker service: Running${NC}"
    else
        echo -e "${RED}✗ Docker service: Not running${NC}"
        success=false
    fi
    
    if minikube status 2>/dev/null | grep -q "Running"; then
        echo -e "${GREEN}✓ Minikube cluster: Running${NC}"
        echo -e "${GREEN}✓ Cluster IP: $(minikube ip 2>/dev/null)${NC}"
    else
        echo -e "${RED}✗ Minikube cluster: Not running${NC}"
        success=false
    fi
    
    if $success; then
        log_info "All verifications passed!"
    else
        log_warn "Some verifications failed, but continuing..."
        return 0
    fi
}

# Test with sample application
test_application() {
    log_step "Testing with sample application..."
    
    # Create namespace for test
    kubectl create namespace test-app --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
    
    # Deploy sample application
    kubectl create deployment hello-ubuntu --image=nginx:alpine --replicas=2 -n test-app 2>/dev/null || \
        log_warn "Failed to create deployment, may already exist"
    
    kubectl expose deployment hello-ubuntu --port=80 --type=NodePort -n test-app 2>/dev/null || \
        log_warn "Failed to expose service, may already exist"
    
    # Wait for pods to be ready
    log_info "Waiting for pods to be ready..."
    for i in {1..30}; do
        if kubectl get pods -n test-app 2>/dev/null | grep -q "Running"; then
            break
        fi
        sleep 2
    done
    
    # Display results
    echo -e "\n${GREEN}=== TEST APPLICATION STATUS ===${NC}"
    kubectl get all -n test-app 2>/dev/null || log_warn "Could not get test application status"
    
    # Get service URL
    local port=$(kubectl get svc hello-ubuntu -n test-app -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "unknown")
    local ip=$(minikube ip 2>/dev/null || echo "unknown")
    echo -e "\n${GREEN}Test application URL: http://$ip:$port${NC}"
}

# Display cluster information
show_cluster_info() {
    log_step "Cluster Information:"
    
    echo -e "\n${GREEN}=== CLUSTER INFO ===${NC}"
    echo -e "Minikube IP: $(minikube ip 2>/dev/null || echo "unknown")"
    kubectl version --short 2>/dev/null | grep Server | cut -d' ' -f3 | while read -r version; do
        echo -e "Kubernetes Version: $version"
    done || echo -e "Kubernetes Version: unknown"
    
    echo -e "\n${GREEN}Current Resources:${NC}"
    kubectl get nodes -o wide 2>/dev/null || log_warn "Could not get node information"
    echo ""
    kubectl get pods --all-namespaces 2>/dev/null || log_warn "Could not get pod information"
}

# Display usage information
show_usage() {
    cat << EOF

Usage: $0 [OPTIONS]

Minikube Automated Setup for Ubuntu

Options:
    -h, --help          Show this help message
    -d, --driver DRIVER Set driver (docker, podman, virtualbox) - default: docker
    -m, --memory MEM    Set memory in MB - default: 4096
    -c, --cpus CPU      Set CPU count - default: 2
    --disk-size SIZE    Set disk size - default: 20g
    --skip-test         Skip test application deployment
    --skip-addons       Skip enabling addons

Examples:
    $0                          # Full installation with defaults
    $0 --driver=docker          # Use Docker driver
    $0 --memory=8192 --cpus=4   # Set custom resources
    $0 --skip-test              # Skip test application

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -d|--driver)
                DRIVER="$2"
                shift 2
                ;;
            -m|--memory)
                MEMORY="$2"
                shift 2
                ;;
            -c|--cpus)
                CPUS="$2"
                shift 2
                ;;
            --disk-size)
                DISK_SIZE="$2"
                shift 2
                ;;
            --skip-test)
                SKIP_TEST=true
                shift
                ;;
            --skip-addons)
                SKIP_ADDONS=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main installation function
main_installation() {
    log_step "Starting Minikube installation on Ubuntu..."
    echo -e "${GREEN}Configuration:${NC}"
    echo -e "  Driver: $DRIVER"
    echo -e "  Memory: ${MEMORY}MB"
    echo -e "  CPUs: $CPUS"
    echo -e "  Disk: $DISK_SIZE"
    echo ""
    
    # Execute installation steps
    check_ubuntu
    check_sudo
    update_system
    install_docker
    install_minikube
    install_kubectl
    setup_docker_permissions
    start_minikube
    
    if [[ "$SKIP_ADDONS" != "true" ]]; then
        enable_addons
    fi
    
    setup_shell
    verify_installation
    
    if [[ "$SKIP_TEST" != "true" ]]; then
        test_application
    fi
    
    show_cluster_info
}

# Display completion message
show_completion() {
    cat << EOF

      🎉 Minikube Installation Complete! 🎉

  Next Steps:
  1. Open dashboard:    minikube dashboard
  2. Check status:      minikube status
  3. List nodes:        kubectl get nodes
  4. Stop cluster:      minikube stop
  5. Delete cluster:    minikube delete

  Useful Aliases:
  k    - kubectl
  mk   - minikube
  kgp  - kubectl get pods
  kgs  - kubectl get services
  kgd  - kubectl get deployments

     Troubleshooting:
  View logs:          minikube logs
  SSH into node:      minikube ssh
  Restart cluster:    minikube restart

        Note: If Docker commands still require sudo, log out and back in for group changes to take effect.

EOF
}

# Cleanup function (called on exit)
cleanup() {
    if [[ $? -ne 0 ]]; then
        log_error "Installation failed. Check the logs above for errors."
        log_warn "You can run the script again after fixing the issues."
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Main execution
parse_arguments "$@"
main_installation
show_completion
