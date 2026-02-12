#!/usr/bin/env bash
# 07-deploy-apps.sh - Deploy custom business applications
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Load environment variables
load_env

log_info "=== Step 7: Deploying custom applications ==="

# Ensure openfaas-fn namespace exists
kubectl create namespace openfaas-fn 2>/dev/null || true

# --- Create secrets ---
log_info "Creating application secrets..."

# HuggingFace token secret
if [ -n "${HF_TOKEN:-}" ]; then
    kubectl create secret generic app-secrets \
        --namespace openfaas-fn \
        --from-literal=hf-token="$HF_TOKEN" \
        --dry-run=client -o yaml | kubectl apply -f -
    log_success "app-secrets created with HF_TOKEN."
else
    log_warn "HF_TOKEN not set. fastapi-llama may not function properly."
    # Create an empty secret so the deployment doesn't fail on secretKeyRef
    kubectl create secret generic app-secrets \
        --namespace openfaas-fn \
        --from-literal=hf-token="" \
        --dry-run=client -o yaml | kubectl apply -f -
fi

# NGC Docker registry secret (optional)
if [ -n "${NGC_DOCKER_CONFIG:-}" ]; then
    kubectl create secret docker-registry ngc-secret \
        --namespace openfaas-fn \
        --docker-server=nvcr.io \
        --docker-username='$oauthtoken' \
        --docker-password="${NGC_API_KEY:-}" \
        --dry-run=client -o yaml | kubectl apply -f -
    log_success "ngc-secret created."
fi

# --- Check for local image: fastapi-llama:abc ---
log_info "Checking for local image 'fastapi-llama:abc'..."
if ctr -n k8s.io images check name==docker.io/library/fastapi-llama:abc 2>/dev/null | grep -q "fastapi-llama"; then
    log_success "Image 'fastapi-llama:abc' found in containerd."
else
    log_warn "========================================================"
    log_warn "Image 'fastapi-llama:abc' NOT found in containerd."
    log_warn "The fastapi-llama deployment uses a local image."
    log_warn ""
    log_warn "You need to either:"
    log_warn "  1. Build the image locally:"
    log_warn "     docker build -t fastapi-llama:abc /path/to/Dockerfile"
    log_warn "     docker save fastapi-llama:abc | ctr -n k8s.io images import -"
    log_warn "  2. Import a pre-exported image:"
    log_warn "     ctr -n k8s.io images import fastapi-llama.tar"
    log_warn "  3. Change the image in manifests/apps/fastapi-llama.yaml"
    log_warn "     to point to a registry."
    log_warn "========================================================"
    log_warn "Continuing deployment (fastapi-llama pod may fail to start)..."
fi

# --- Deploy applications ---
log_info "Deploying fastapi-llama..."
kubectl apply -f "${PROJECT_ROOT}/manifests/apps/fastapi-llama.yaml"

log_info "Deploying modelproc..."
kubectl apply -f "${PROJECT_ROOT}/manifests/apps/modelproc.yaml"

log_info "Deploying userdataproc-user-a..."
kubectl apply -f "${PROJECT_ROOT}/manifests/apps/userdataproc-user-a.yaml"

log_info "Deploying userdataproc-user-b..."
kubectl apply -f "${PROJECT_ROOT}/manifests/apps/userdataproc-user-b.yaml"

# Wait for deployments
log_info "Waiting for application pods..."
sleep 10
for app in modelproc userdataproc-user-a userdataproc-user-b; do
    wait_for_deployment "$app" "openfaas-fn" 120 || true
done
# fastapi-llama may take longer due to model loading
wait_for_deployment "fastapi-llama" "openfaas-fn" 300 || true

# Show status
log_info "Application pod status:"
kubectl get pods -n openfaas-fn

log_success "=== Custom applications deployed ==="
