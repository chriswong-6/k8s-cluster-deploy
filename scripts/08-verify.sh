#!/usr/bin/env bash
# 08-verify.sh - Verify deployment status
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

log_info "============================================"
log_info "   Deployment Verification"
log_info "============================================"

FAILURES=0

# --- 1. Node status ---
log_info "--- Checking node status ---"
NODE_STATUS=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}')
if echo "$NODE_STATUS" | grep -q "Ready"; then
    log_success "Node is Ready."
    kubectl get nodes -o wide
else
    log_error "Node is NOT Ready!"
    FAILURES=$((FAILURES + 1))
fi

# --- 2. System pods ---
log_info ""
log_info "--- Checking system pods (kube-system) ---"
NOT_RUNNING=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v "Running\|Completed" || true)
if [ -z "$NOT_RUNNING" ]; then
    log_success "All kube-system pods are Running."
else
    log_warn "Some kube-system pods are not Running:"
    echo "$NOT_RUNNING"
    FAILURES=$((FAILURES + 1))
fi

# --- 3. GPU availability ---
log_info ""
log_info "--- Checking GPU availability ---"
if nvidia-smi &>/dev/null; then
    log_success "nvidia-smi is functional."
    nvidia-smi --query-gpu=name,driver_version,memory.total,memory.free --format=csv,noheader
else
    log_error "nvidia-smi failed!"
    FAILURES=$((FAILURES + 1))
fi

# Check GPU schedulable in K8s
GPU_COUNT=$(kubectl get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null || echo "0")
log_info "K8s allocatable GPUs (nvidia.com/gpu): ${GPU_COUNT:-0}"

# Check Koordinator GPU devices
if kubectl get devices.scheduling.koordinator.sh &>/dev/null 2>&1; then
    log_success "Koordinator GPU devices are registered."
    kubectl get devices.scheduling.koordinator.sh 2>/dev/null || true
else
    log_info "Koordinator GPU devices CRD not found (may use different resource names)."
fi

# --- 4. Component status per namespace ---
log_info ""
log_info "--- Checking component pods ---"
for ns in koordinator-system ingress-nginx openfaas openfaas-fn monitoring local-path-storage; do
    NOT_RUNNING=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -v "Running\|Completed" || true)
    TOTAL=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)
    if [ "$TOTAL" -eq 0 ]; then
        log_warn "[$ns] No pods found."
    elif [ -z "$NOT_RUNNING" ]; then
        log_success "[$ns] All $TOTAL pod(s) are Running."
    else
        log_warn "[$ns] Some pods are not Running:"
        echo "$NOT_RUNNING"
        FAILURES=$((FAILURES + 1))
    fi
done

# Check Akash if deployed
AKASH_PODS=$(kubectl get pods -n akash-services --no-headers 2>/dev/null | wc -l)
if [ "$AKASH_PODS" -gt 0 ]; then
    NOT_RUNNING=$(kubectl get pods -n akash-services --no-headers 2>/dev/null | grep -v "Running\|Completed" || true)
    if [ -z "$NOT_RUNNING" ]; then
        log_success "[akash-services] All pods are Running."
    else
        log_warn "[akash-services] Some pods are not Running:"
        echo "$NOT_RUNNING"
    fi
fi

# --- 5. Service endpoints ---
log_info ""
log_info "--- Checking service endpoints ---"

# OpenFaaS Gateway
OPENFAAS_PORT=$(kubectl get svc gateway-external -n openfaas -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "31112")
if curl -s --max-time 5 "http://localhost:${OPENFAAS_PORT}/healthz" &>/dev/null; then
    log_success "OpenFaaS Gateway is accessible at http://localhost:${OPENFAAS_PORT}/ui"
else
    log_warn "OpenFaaS Gateway is not responding on port ${OPENFAAS_PORT}."
fi

# Grafana
GRAFANA_PORT=$(kubectl get svc prometheus-grafana -n monitoring -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
if [ -n "$GRAFANA_PORT" ]; then
    if curl -s --max-time 5 "http://localhost:${GRAFANA_PORT}" &>/dev/null; then
        log_success "Grafana is accessible at http://localhost:${GRAFANA_PORT}"
    else
        log_warn "Grafana is not responding on port ${GRAFANA_PORT}."
    fi
else
    GRAFANA_CLUSTER_PORT=$(kubectl get svc prometheus-grafana -n monitoring -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "80")
    log_info "Grafana is running as ClusterIP. Access via: kubectl port-forward svc/prometheus-grafana -n monitoring 3000:${GRAFANA_CLUSTER_PORT}"
fi

# fastapi-llama
LLAMA_PORT=$(kubectl get svc fastapi-llama-service -n openfaas-fn -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "30800")
if curl -s --max-time 5 "http://localhost:${LLAMA_PORT}" &>/dev/null; then
    log_success "fastapi-llama is accessible at http://localhost:${LLAMA_PORT}"
else
    log_warn "fastapi-llama is not responding on port ${LLAMA_PORT} (may still be loading model)."
fi

# --- Summary ---
log_info ""
log_info "============================================"
if [ "$FAILURES" -eq 0 ]; then
    log_success "   ALL CHECKS PASSED"
else
    log_warn "   $FAILURES check(s) had warnings/failures"
fi
log_info "============================================"
log_info ""
log_info "Quick access:"
log_info "  OpenFaaS UI:    http://localhost:31112/ui"
log_info "  fastapi-llama:  http://localhost:30800"
log_info "  Grafana:        kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80"
log_info ""

# Print OpenFaaS credentials if available
if kubectl get secret -n openfaas basic-auth &>/dev/null; then
    OPENFAAS_PASS=$(kubectl get secret -n openfaas basic-auth -o jsonpath='{.data.basic-auth-password}' | base64 -d 2>/dev/null || echo "unknown")
    log_info "OpenFaaS credentials: admin / ${OPENFAAS_PASS}"
fi

exit $FAILURES
