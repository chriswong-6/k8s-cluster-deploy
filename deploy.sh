#!/usr/bin/env bash
# deploy.sh - One-click deployment of K8s cluster with GPU support
#
# Usage:
#   sudo ./deploy.sh                  # Full deployment
#   sudo ./deploy.sh --skip-k8s       # Skip K8s install (if already installed)
#   sudo ./deploy.sh --skip-nvidia    # Skip NVIDIA driver install
#   sudo ./deploy.sh --apps-only      # Only deploy applications (K8s + components assumed ready)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${SCRIPT_DIR}/scripts"

# Parse arguments
SKIP_K8S=false
SKIP_NVIDIA=false
APPS_ONLY=false

for arg in "$@"; do
    case $arg in
        --skip-k8s)
            SKIP_K8S=true
            ;;
        --skip-nvidia)
            SKIP_NVIDIA=true
            ;;
        --apps-only)
            APPS_ONLY=true
            ;;
        --help|-h)
            echo "Usage: sudo ./deploy.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-k8s       Skip Kubernetes installation (steps 0-3)"
            echo "  --skip-nvidia    Skip NVIDIA driver installation (step 4)"
            echo "  --apps-only      Only deploy applications (steps 6-7)"
            echo "  --help, -h       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

source "${SCRIPTS}/utils.sh"

# Check running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root (use sudo)."
    exit 1
fi

# Load environment variables
if [ -f "${SCRIPT_DIR}/.env" ]; then
    log_info "Loading configuration from .env file..."
    set -a
    source "${SCRIPT_DIR}/.env"
    set +a
else
    log_warn "No .env file found. Copy .env.example to .env and configure it."
    log_warn "Continuing with defaults (some features may not work)..."
fi

log_info "============================================"
log_info "   K8s Cluster Deployment"
log_info "============================================"
log_info ""
log_info "Options:"
log_info "  Skip K8s install:     $SKIP_K8S"
log_info "  Skip NVIDIA install:  $SKIP_NVIDIA"
log_info "  Apps only:            $APPS_ONLY"
log_info ""

STEP_START_TIME=$SECONDS

run_step() {
    local step_name="$1"
    local step_script="$2"
    local step_start=$SECONDS

    log_info ">>> Running: $step_name"
    if bash "$step_script"; then
        local elapsed=$((SECONDS - step_start))
        log_success ">>> Completed: $step_name (${elapsed}s)"
    else
        log_error ">>> FAILED: $step_name"
        log_error "Fix the issue and re-run: sudo bash $step_script"
        log_error "Then re-run deploy.sh to continue from where it left off."
        exit 1
    fi
    echo ""
}

if [ "$APPS_ONLY" = true ]; then
    # Only deploy applications
    run_step "Deploy Helm components" "${SCRIPTS}/06-deploy-components.sh"
    run_step "Deploy applications" "${SCRIPTS}/07-deploy-apps.sh"
else
    if [ "$SKIP_K8S" = false ]; then
        run_step "Prerequisites" "${SCRIPTS}/00-prerequisites.sh"
        run_step "Install containerd" "${SCRIPTS}/01-install-containerd.sh"
        run_step "Install Kubernetes" "${SCRIPTS}/02-install-kubernetes.sh"
        run_step "Install Calico CNI" "${SCRIPTS}/03-install-calico.sh"
    else
        log_info "Skipping K8s installation (--skip-k8s)"
    fi

    if [ "$SKIP_NVIDIA" = false ]; then
        run_step "Install NVIDIA stack" "${SCRIPTS}/04-install-nvidia.sh"
    else
        log_info "Skipping NVIDIA installation (--skip-nvidia)"
    fi

    run_step "Install Helm" "${SCRIPTS}/05-install-helm.sh"
    run_step "Deploy Helm components" "${SCRIPTS}/06-deploy-components.sh"
    run_step "Deploy applications" "${SCRIPTS}/07-deploy-apps.sh"
fi

# Verification
run_step "Verify deployment" "${SCRIPTS}/08-verify.sh"

TOTAL_TIME=$((SECONDS - STEP_START_TIME))
log_info ""
log_success "============================================"
log_success "   Deployment completed in ${TOTAL_TIME}s"
log_success "============================================"
