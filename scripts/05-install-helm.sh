#!/usr/bin/env bash
# 05-install-helm.sh - Install Helm 3
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

log_info "=== Step 5: Installing Helm ==="

if check_command helm; then
    HELM_VER=$(helm version --short 2>/dev/null | head -1)
    log_info "Helm is already installed (version: $HELM_VER). Skipping."
else
    log_info "Installing Helm 3..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    log_success "Helm installed."
fi

# Add required Helm repositories
log_info "Adding Helm repositories..."

helm repo add koordinator-sh https://koordinator-sh.github.io/charts 2>/dev/null || true
helm repo add openfaas https://openfaas.github.io/faas-netes 2>/dev/null || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo add akash https://ovrclk.github.io/helm-charts 2>/dev/null || true

log_info "Updating Helm repositories..."
helm repo update
log_success "Helm repositories configured."

log_success "=== Helm installation completed ==="
