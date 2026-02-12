#!/usr/bin/env bash
# 02-install-kubernetes.sh - Install kubeadm, kubelet, kubectl and initialize cluster
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${SCRIPT_DIR}/utils.sh"

K8S_VERSION="1.28"

log_info "=== Step 2: Installing Kubernetes v${K8S_VERSION} ==="

if check_command kubeadm; then
    INSTALLED_VERSION=$(kubeadm version -o short 2>/dev/null || echo "unknown")
    log_info "kubeadm is already installed (version: $INSTALLED_VERSION)."
else
    # Add Kubernetes apt repository
    log_info "Adding Kubernetes apt repository..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" | \
        gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>/dev/null

    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | \
        tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

    apt-get update -qq
    log_info "Installing kubeadm, kubelet, kubectl..."
    apt-get install -y -qq kubelet kubeadm kubectl >/dev/null 2>&1

    # Prevent auto-upgrades
    apt-mark hold kubelet kubeadm kubectl
    log_success "Kubernetes components installed."
fi

# Check if cluster is already initialized
if [ -f /etc/kubernetes/admin.conf ]; then
    log_info "Kubernetes cluster appears to already be initialized."
    log_info "Skipping kubeadm init. If you want to reinitialize, run 'kubeadm reset' first."
else
    # Initialize the cluster
    log_info "Initializing Kubernetes cluster with kubeadm..."
    kubeadm init --config="${PROJECT_ROOT}/configs/kubeadm-config.yaml" \
        --upload-certs \
        2>&1 | tee /tmp/kubeadm-init.log

    log_success "Kubernetes cluster initialized."
fi

# Configure kubectl for the current user (root)
log_info "Configuring kubectl access..."
export KUBECONFIG=/etc/kubernetes/admin.conf
mkdir -p "$HOME/.kube"
cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
chown "$(id -u):$(id -g)" "$HOME/.kube/config"

# Also set up for the original user if running via sudo
if [ -n "${SUDO_USER:-}" ]; then
    USER_HOME=$(eval echo "~$SUDO_USER")
    mkdir -p "${USER_HOME}/.kube"
    cp -f /etc/kubernetes/admin.conf "${USER_HOME}/.kube/config"
    chown "$(id -u "$SUDO_USER"):$(id -g "$SUDO_USER")" "${USER_HOME}/.kube/config"
    log_info "kubectl configured for user $SUDO_USER"
fi

# Untaint control-plane node (single-node cluster)
log_info "Untainting control-plane node for single-node setup..."
kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true
log_success "Control-plane taint removed."

# Install metrics-server
log_info "Installing metrics-server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml 2>/dev/null || true
# Patch metrics-server for single-node (insecure TLS)
kubectl patch deployment metrics-server -n kube-system --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' 2>/dev/null || true
log_success "metrics-server installed."

# Verify cluster is running
log_info "Verifying cluster status..."
if kubectl cluster-info &>/dev/null; then
    log_success "Kubernetes cluster is running."
    kubectl get nodes
else
    log_error "Cluster is not responding. Check: journalctl -u kubelet"
    exit 1
fi

log_success "=== Kubernetes installation completed ==="
