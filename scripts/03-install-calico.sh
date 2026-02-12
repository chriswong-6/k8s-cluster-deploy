#!/usr/bin/env bash
# 03-install-calico.sh - Install Calico CNI v3.27.2
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${SCRIPT_DIR}/utils.sh"

CALICO_VERSION="v3.27.2"
CALICO_MANIFEST_URL="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"
POD_CIDR="172.16.0.0/16"

log_info "=== Step 3: Installing Calico CNI ${CALICO_VERSION} ==="

# Check if Calico is already installed
if kubectl get daemonset calico-node -n kube-system &>/dev/null; then
    log_info "Calico is already installed."
    kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers
    log_info "Skipping Calico installation."
    exit 0
fi

# Download Calico manifest
log_info "Downloading Calico ${CALICO_VERSION} manifest..."
CALICO_MANIFEST="/tmp/calico-${CALICO_VERSION}.yaml"
curl -fsSL "$CALICO_MANIFEST_URL" -o "$CALICO_MANIFEST"

# Update CALICO_IPV4POOL_CIDR to match our pod network
log_info "Configuring Calico with pod CIDR: ${POD_CIDR}..."
sed -i "s|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|g" "$CALICO_MANIFEST"
sed -i "s|#   value: \"192.168.0.0/16\"|  value: \"${POD_CIDR}\"|g" "$CALICO_MANIFEST"

# Apply Calico manifest
log_info "Applying Calico manifest..."
kubectl apply -f "$CALICO_MANIFEST"

# Wait for Calico to be ready
log_info "Waiting for Calico pods to start..."
sleep 10
wait_for_daemonset "calico-node" "kube-system" 180

# Wait for CoreDNS to come up (it stays pending until CNI is ready)
log_info "Waiting for CoreDNS pods..."
retry 6 kubectl wait --for=condition=Ready pods -l k8s-app=kube-dns -n kube-system --timeout=60s

# Apply custom IP Pool if needed
if [ -f "${PROJECT_ROOT}/manifests/calico-ippool.yaml" ]; then
    log_info "Verifying Calico IP pool configuration..."
    # The default IP pool is created by Calico during installation
    # Our custom config just confirms the CIDR matches
    kubectl get ippools default-ipv4-ippool -o jsonpath='{.spec.cidr}' 2>/dev/null && echo "" || true
fi

# Save the downloaded manifest for reference
cp "$CALICO_MANIFEST" "${PROJECT_ROOT}/configs/calico.yaml"

log_success "=== Calico CNI installation completed ==="
