#!/usr/bin/env bash
# uninstall.sh - Remove deployed components (reverse order)
#
# Usage:
#   sudo ./uninstall.sh               # Remove Helm releases + applications
#   sudo ./uninstall.sh --apps-only   # Only remove custom applications
#   sudo ./uninstall.sh --full        # Full teardown: K8s + drivers + packages
#   sudo ./uninstall.sh --full --keep-nvidia  # Full teardown but keep NVIDIA drivers
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/utils.sh"

APPS_ONLY=false
FULL_RESET=false
KEEP_NVIDIA=false

for arg in "$@"; do
    case $arg in
        --apps-only)
            APPS_ONLY=true
            ;;
        --full)
            FULL_RESET=true
            ;;
        --keep-nvidia)
            KEEP_NVIDIA=true
            ;;
        --help|-h)
            echo "Usage: sudo ./uninstall.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --apps-only     Only remove custom applications"
            echo "  --full          Full teardown: K8s + drivers + packages"
            echo "  --keep-nvidia   With --full: keep NVIDIA drivers installed"
            echo "  --help, -h      Show this help message"
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

# Clean up Akash PVCs and secrets
log_info "Cleaning up Akash PVCs and secrets..."
kubectl delete pvc --all -n akash-services --ignore-not-found 2>/dev/null || true
kubectl delete secret akash-provider-keys -n akash-services --ignore-not-found 2>/dev/null || true

# Akash CRDs
log_info "Removing Akash CRDs..."
kubectl delete -f "${SCRIPT_DIR}/manifests/akash-crds/" --ignore-not-found 2>/dev/null || true

# kube-prometheus-stack
if helm status prometheus -n monitoring &>/dev/null; then
    log_info "Uninstalling kube-prometheus-stack..."
    helm uninstall prometheus -n monitoring 2>/dev/null || true
fi

# Prometheus CRDs (Helm uninstall does not remove these)
log_info "Removing Prometheus CRDs..."
kubectl delete crd alertmanagerconfigs.monitoring.coreos.com --ignore-not-found 2>/dev/null || true
kubectl delete crd alertmanagers.monitoring.coreos.com --ignore-not-found 2>/dev/null || true
kubectl delete crd podmonitors.monitoring.coreos.com --ignore-not-found 2>/dev/null || true
kubectl delete crd probes.monitoring.coreos.com --ignore-not-found 2>/dev/null || true
kubectl delete crd prometheusagents.monitoring.coreos.com --ignore-not-found 2>/dev/null || true
kubectl delete crd prometheuses.monitoring.coreos.com --ignore-not-found 2>/dev/null || true
kubectl delete crd prometheusrules.monitoring.coreos.com --ignore-not-found 2>/dev/null || true
kubectl delete crd scrapeconfigs.monitoring.coreos.com --ignore-not-found 2>/dev/null || true
kubectl delete crd servicemonitors.monitoring.coreos.com --ignore-not-found 2>/dev/null || true
kubectl delete crd thanosrulers.monitoring.coreos.com --ignore-not-found 2>/dev/null || true

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

# Koordinator CRDs
log_info "Removing Koordinator CRDs..."
kubectl get crd -o name 2>/dev/null | grep -E 'koordinator|slo\.koordinator' | xargs -r kubectl delete --ignore-not-found 2>/dev/null || true

# local-path-provisioner
kubectl delete -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml --ignore-not-found 2>/dev/null || true

log_success "Helm releases removed."

# --- Remove StorageClasses and namespaces ---
log_info "--- Cleaning up resources ---"
kubectl delete -f "${SCRIPT_DIR}/manifests/storage-classes.yaml" --ignore-not-found 2>/dev/null || true

# Delete all custom namespaces
for ns in openfaas openfaas-fn monitoring akash-services nim-service lease koordinator-system ingress-nginx local-path-storage; do
    kubectl delete namespace "$ns" --ignore-not-found 2>/dev/null || true
done
log_success "Resources cleaned up."

if [ "$FULL_RESET" = true ]; then
    log_warn "============================================"
    log_warn "   Full reset: removing everything"
    log_warn "============================================"

    # --- Kubernetes teardown ---
    log_info "Running kubeadm reset..."
    kubeadm reset -f 2>/dev/null || true

    # Clean up CNI
    rm -rf /etc/cni/net.d/*
    rm -rf /var/lib/cni/
    rm -rf /var/lib/calico/

    # Clean up kubelet data
    rm -rf /var/lib/kubelet/

    # Clean up etcd data
    rm -rf /var/lib/etcd/

    # Clean up iptables
    iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X 2>/dev/null || true
    ip6tables -F && ip6tables -t nat -F && ip6tables -t mangle -F && ip6tables -X 2>/dev/null || true

    # Clean up kubeconfig
    rm -rf "$HOME/.kube/config"
    rm -rf /etc/kubernetes/

    # --- NVIDIA MPS ---
    log_info "Stopping NVIDIA MPS..."
    systemctl stop nvidia-mps.service 2>/dev/null || true
    systemctl disable nvidia-mps.service 2>/dev/null || true
    rm -f /etc/systemd/system/nvidia-mps.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true

    # --- Remove Helm ---
    log_info "Removing Helm..."
    rm -f /usr/local/bin/helm 2>/dev/null || true
    rm -rf "$HOME/.cache/helm" "$HOME/.config/helm" "$HOME/.local/share/helm" 2>/dev/null || true

    # --- Remove Kubernetes packages ---
    log_info "Removing kubelet, kubeadm, kubectl..."
    apt-mark unhold kubelet kubeadm kubectl 2>/dev/null || true
    apt-get purge -y kubelet kubeadm kubectl 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/kubernetes.list 2>/dev/null || true
    rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>/dev/null || true

    # --- Remove containerd ---
    log_info "Removing containerd..."
    systemctl stop containerd 2>/dev/null || true
    apt-get purge -y containerd.io 2>/dev/null || true
    rm -rf /var/lib/containerd/
    rm -rf /etc/containerd/
    rm -f /etc/apt/sources.list.d/docker.list 2>/dev/null || true
    rm -f /etc/apt/keyrings/docker.gpg 2>/dev/null || true

    # --- Remove NVIDIA drivers and container toolkit ---
    if [ "$KEEP_NVIDIA" = true ]; then
        log_info "Keeping NVIDIA drivers (--keep-nvidia). Only removing container toolkit..."
        apt-get purge -y nvidia-container-toolkit 2>/dev/null || true
        rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list 2>/dev/null || true
    else
        log_info "Removing NVIDIA Container Toolkit..."
        apt-get purge -y nvidia-container-toolkit 2>/dev/null || true
        rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list 2>/dev/null || true

        log_info "Removing NVIDIA drivers..."
        apt-get purge -y 'nvidia-driver-*' 'libnvidia-*' 'nvidia-utils-*' 2>/dev/null || true
        apt-get purge -y 'cuda-*' 'nvidia-cuda-*' 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
        rm -rf /usr/local/cuda* 2>/dev/null || true
        rm -f /etc/apt/sources.list.d/cuda*.list 2>/dev/null || true

        log_info "Removing NVIDIA kernel modules..."
        rmmod nvidia_uvm nvidia_drm nvidia_modeset nvidia 2>/dev/null || true
    fi

    # --- Final cleanup ---
    log_info "Running final apt cleanup..."
    apt-get autoremove -y 2>/dev/null || true
    apt-get clean 2>/dev/null || true

    log_success "============================================"
    log_success "   Full reset completed"
    log_success "============================================"
    log_info "System is clean. Reboot recommended: sudo reboot"
fi

log_success "============================================"
log_success "   Uninstall completed"
log_success "============================================"
