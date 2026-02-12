#!/usr/bin/env bash
# uninstall.sh - Remove deployed components (reverse order)
#
# Usage:
#   sudo ./uninstall.sh               # Remove all components
#   sudo ./uninstall.sh --apps-only   # Only remove custom applications
#   sudo ./uninstall.sh --full        # Full teardown including kubeadm reset
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/utils.sh"

APPS_ONLY=false
FULL_RESET=false

for arg in "$@"; do
    case $arg in
        --apps-only)
            APPS_ONLY=true
            ;;
        --full)
            FULL_RESET=true
            ;;
        --help|-h)
            echo "Usage: sudo ./uninstall.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --apps-only   Only remove custom applications"
            echo "  --full        Full teardown including kubeadm reset"
            echo "  --help, -h    Show this help message"
            exit 0
            ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root."
    exit 1
fi

log_info "============================================"
log_info "   K8s Cluster Uninstall"
log_info "============================================"

# --- Remove custom applications ---
log_info "--- Removing custom applications ---"
kubectl delete -f "${SCRIPT_DIR}/manifests/apps/" --ignore-not-found 2>/dev/null || true
kubectl delete secret app-secrets -n openfaas-fn --ignore-not-found 2>/dev/null || true
kubectl delete secret ngc-secret -n openfaas-fn --ignore-not-found 2>/dev/null || true
log_success "Custom applications removed."

if [ "$APPS_ONLY" = true ]; then
    log_success "Apps-only uninstall completed."
    exit 0
fi

# --- Remove Helm releases (reverse order) ---
log_info "--- Removing Helm releases ---"

# NeMo CRDs
kubectl delete -f "${SCRIPT_DIR}/manifests/nemo-crds/" --ignore-not-found 2>/dev/null || true

# Akash components
for release in inventory-operator akash-hostname-operator akash-provider; do
    if helm status "$release" -n akash-services &>/dev/null; then
        log_info "Uninstalling $release..."
        helm uninstall "$release" -n akash-services 2>/dev/null || true
    fi
done

# kube-prometheus-stack
if helm status prometheus -n monitoring &>/dev/null; then
    log_info "Uninstalling kube-prometheus-stack..."
    helm uninstall prometheus -n monitoring 2>/dev/null || true
fi

# OpenFaaS
if helm status openfaas -n openfaas &>/dev/null; then
    log_info "Uninstalling OpenFaaS..."
    helm uninstall openfaas -n openfaas 2>/dev/null || true
fi

# ingress-nginx
if helm status ingress-nginx -n ingress-nginx &>/dev/null; then
    log_info "Uninstalling ingress-nginx..."
    helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null || true
fi

# Koordinator
if helm status koordinator -n default &>/dev/null; then
    log_info "Uninstalling Koordinator..."
    helm uninstall koordinator -n default 2>/dev/null || true
fi

# local-path-provisioner
kubectl delete -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml --ignore-not-found 2>/dev/null || true

log_success "Helm releases removed."

# --- Remove StorageClasses and namespaces ---
log_info "--- Cleaning up resources ---"
kubectl delete -f "${SCRIPT_DIR}/manifests/storage-classes.yaml" --ignore-not-found 2>/dev/null || true

# Delete custom namespaces
for ns in openfaas openfaas-fn monitoring akash-services nim-service lease; do
    kubectl delete namespace "$ns" --ignore-not-found 2>/dev/null || true
done
log_success "Resources cleaned up."

if [ "$FULL_RESET" = true ]; then
    log_warn "--- Full reset: tearing down Kubernetes ---"

    # kubeadm reset
    log_info "Running kubeadm reset..."
    kubeadm reset -f 2>/dev/null || true

    # Clean up CNI
    rm -rf /etc/cni/net.d/*
    rm -rf /var/lib/cni/
    rm -rf /var/lib/calico/

    # Clean up iptables
    iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X 2>/dev/null || true

    # Clean up kubeconfig
    rm -rf "$HOME/.kube/config"

    # Stop NVIDIA MPS
    systemctl stop nvidia-mps.service 2>/dev/null || true
    systemctl disable nvidia-mps.service 2>/dev/null || true

    log_success "Full Kubernetes reset completed."
    log_info "Note: NVIDIA drivers and containerd are still installed."
    log_info "To remove them: apt remove nvidia-driver-560 containerd.io"
fi

log_success "============================================"
log_success "   Uninstall completed"
log_success "============================================"
