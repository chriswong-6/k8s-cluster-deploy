#!/usr/bin/env bash
# 06-deploy-components.sh - Deploy all Helm chart components in dependency order
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Load environment variables for template substitution
load_env

DEPLOY_AKASH="${DEPLOY_AKASH:-false}"
DEPLOY_NEMO="${DEPLOY_NEMO:-false}"

log_info "=== Step 6: Deploying Helm chart components ==="

# Create namespaces first
log_info "Creating namespaces..."
kubectl apply -f "${PROJECT_ROOT}/manifests/namespaces.yaml"
log_success "Namespaces created."

# Apply StorageClass definitions
log_info "Applying StorageClass definitions..."
kubectl apply -f "${PROJECT_ROOT}/manifests/storage-classes.yaml"
log_success "StorageClasses created."

# --- 1. local-path-provisioner ---
log_info "--- Deploying local-path-provisioner ---"
if helm status local-path-provisioner -n local-path-storage &>/dev/null; then
    log_info "local-path-provisioner is already installed. Skipping."
else
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml 2>/dev/null || {
        log_warn "Failed to install local-path-provisioner from URL, trying Helm..."
        helm install local-path-provisioner \
            --namespace local-path-storage \
            --create-namespace \
            https://github.com/rancher/local-path-provisioner/archive/refs/tags/v0.0.26.tar.gz \
            -f "${PROJECT_ROOT}/helm-values/local-path-values.yaml" || true
    }
fi
log_success "local-path-provisioner deployed."

# --- 2. Koordinator + HAMi (GPU scheduling) ---
log_info "--- Deploying Koordinator v1.6.0 ---"
if helm status koordinator -n default &>/dev/null; then
    log_info "Koordinator is already installed. Skipping."
else
    # Label the namespace so Helm can adopt it
    kubectl label namespace koordinator-system app.kubernetes.io/managed-by=Helm --overwrite 2>/dev/null || true
    kubectl annotate namespace koordinator-system meta.helm.sh/release-name=koordinator meta.helm.sh/release-namespace=default --overwrite 2>/dev/null || true

    helm install koordinator koordinator-sh/koordinator \
        --version 1.6.0 \
        -f "${PROJECT_ROOT}/helm-values/koordinator-values.yaml" \
        --wait --timeout 300s
fi
log_success "Koordinator deployed."

# Wait for Koordinator webhook to be ready (HAMi depends on it)
log_info "Waiting for Koordinator webhooks to be ready..."
wait_for_deployment "koord-manager" "koordinator-system" 180 || true
sleep 10
log_success "Koordinator is ready."

# --- 3. ingress-nginx ---
log_info "--- Deploying ingress-nginx ---"
if helm status ingress-nginx -n ingress-nginx &>/dev/null; then
    log_info "ingress-nginx is already installed. Skipping."
else
    helm install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --version 4.8.3 \
        -f "${PROJECT_ROOT}/helm-values/ingress-nginx-values.yaml" \
        --wait --timeout 180s
fi
log_success "ingress-nginx deployed."

# --- 4. OpenFaaS ---
log_info "--- Deploying OpenFaaS ---"
if helm status openfaas -n openfaas &>/dev/null; then
    log_info "OpenFaaS is already installed. Skipping."
else
    # Create required namespaces
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: openfaas
  labels:
    role: openfaas-system
    access: openfaas-system
---
apiVersion: v1
kind: Namespace
metadata:
  name: openfaas-fn
  labels:
    role: openfaas-fn
EOF

    helm install openfaas openfaas/openfaas \
        --namespace openfaas \
        --version 14.2.103 \
        -f "${PROJECT_ROOT}/helm-values/openfaas-values.yaml" \
        --wait --timeout 180s
fi
log_success "OpenFaaS deployed."

# Print OpenFaaS credentials
if kubectl get secret -n openfaas basic-auth &>/dev/null; then
    OPENFAAS_PASSWORD=$(kubectl get secret -n openfaas basic-auth -o jsonpath='{.data.basic-auth-password}' | base64 -d 2>/dev/null || echo "unknown")
    log_info "OpenFaaS admin password: $OPENFAAS_PASSWORD"
    log_info "OpenFaaS UI: http://localhost:31112/ui"
fi

# --- 5. kube-prometheus-stack ---
log_info "--- Deploying kube-prometheus-stack ---"
if helm status prometheus -n monitoring &>/dev/null; then
    log_info "kube-prometheus-stack is already installed. Skipping."
else
    # Prepare values with env substitution
    PROM_VALUES="/tmp/prometheus-values-rendered.yaml"
    envsubst < "${PROJECT_ROOT}/helm-values/prometheus-values.yaml" > "$PROM_VALUES"

    helm install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        -f "$PROM_VALUES" \
        --wait --timeout 300s

    rm -f "$PROM_VALUES"
fi
log_success "kube-prometheus-stack deployed."

# --- 6. Akash Provider + Operators (Optional) ---
if [ "$DEPLOY_AKASH" = "true" ]; then
    log_info "--- Deploying Akash Provider ---"

    # Apply Akash CRDs (not included in Helm chart)
    log_info "Applying Akash CRDs..."
    kubectl apply -f "${PROJECT_ROOT}/manifests/akash-crds/akash-crds.yaml"
    log_success "Akash CRDs applied."

    # Validate required Akash env vars
    for var in AKASH_KEY AKASH_KEY_SECRET AKASH_DOMAIN AKASH_NODE AKASH_FROM AKASH_EMAIL; do
        if [ -z "${!var:-}" ]; then
            log_error "Missing required environment variable: $var"
            log_error "Set it in .env file before deploying Akash."
            exit 1
        fi
    done

    # Create akash-provider-keys secret from .env values
    if ! kubectl get secret akash-provider-keys -n akash-services &>/dev/null; then
        log_info "Creating akash-provider-keys secret..."
        kubectl create secret generic akash-provider-keys \
            -n akash-services \
            --from-literal=key.txt="$(echo "${AKASH_KEY}" | base64 -d)" \
            --from-literal=key-pass.txt="${AKASH_KEY_SECRET}"
        # Add Helm ownership labels so Helm can adopt this secret
        kubectl label secret akash-provider-keys -n akash-services \
            app.kubernetes.io/managed-by=Helm
        kubectl annotate secret akash-provider-keys -n akash-services \
            meta.helm.sh/release-name=akash-provider \
            meta.helm.sh/release-namespace=akash-services
        log_success "akash-provider-keys secret created."
    fi

    # Render Akash provider values
    AKASH_VALUES="/tmp/akash-provider-values-rendered.yaml"
    envsubst < "${PROJECT_ROOT}/helm-values/akash-provider-values.yaml" > "$AKASH_VALUES"

    if ! helm status akash-provider -n akash-services &>/dev/null; then
        helm install akash-provider akash/provider \
            --namespace akash-services \
            --create-namespace \
            -f "$AKASH_VALUES" \
            --wait --timeout 180s
    fi
    rm -f "$AKASH_VALUES"
    log_success "Akash Provider deployed."

    # Hostname Operator
    log_info "--- Deploying Akash Hostname Operator ---"
    if ! helm status akash-hostname-operator -n akash-services &>/dev/null; then
        helm install akash-hostname-operator akash/akash-hostname-operator \
            --namespace akash-services \
            -f "${PROJECT_ROOT}/helm-values/akash-hostname-op-values.yaml" \
            --wait --timeout 120s
    fi
    log_success "Akash Hostname Operator deployed."

    # Inventory Operator
    log_info "--- Deploying Akash Inventory Operator ---"
    if ! helm status inventory-operator -n akash-services &>/dev/null; then
        helm install inventory-operator akash/akash-inventory-operator \
            --namespace akash-services \
            -f "${PROJECT_ROOT}/helm-values/inventory-op-values.yaml" \
            --wait --timeout 120s
    fi
    log_success "Akash Inventory Operator deployed."
else
    log_info "Skipping Akash Provider deployment (DEPLOY_AKASH != true)"
fi

# --- 7. NeMo Operator CRDs (Optional) ---
if [ "$DEPLOY_NEMO" = "true" ]; then
    log_info "--- Applying NeMo Operator CRDs ---"
    if [ -f "${PROJECT_ROOT}/manifests/nemo-crds/nemo-operator-crds.yaml" ]; then
        kubectl apply -f "${PROJECT_ROOT}/manifests/nemo-crds/nemo-operator-crds.yaml"
        log_success "NeMo CRDs applied."
    else
        log_warn "NeMo CRDs file not found. Skipping."
    fi
else
    log_info "Skipping NeMo CRDs (DEPLOY_NEMO != true)"
fi

log_success "=== All Helm chart components deployed ==="
