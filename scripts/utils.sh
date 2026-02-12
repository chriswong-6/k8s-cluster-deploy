#!/usr/bin/env bash
# Common utility functions for deployment scripts
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check if a command exists
check_command() {
    if command -v "$1" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Wait for a Kubernetes resource to be ready
wait_for_pods() {
    local namespace="$1"
    local timeout="${2:-300}"
    log_info "Waiting for all pods in namespace '$namespace' to be ready (timeout: ${timeout}s)..."
    if ! kubectl wait --for=condition=Ready pods --all -n "$namespace" --timeout="${timeout}s" 2>/dev/null; then
        log_warn "Some pods in '$namespace' are not ready yet. Continuing..."
        kubectl get pods -n "$namespace" --no-headers 2>/dev/null || true
        return 1
    fi
    log_success "All pods in '$namespace' are ready."
    return 0
}

# Wait for a deployment to be available
wait_for_deployment() {
    local name="$1"
    local namespace="$2"
    local timeout="${3:-300}"
    log_info "Waiting for deployment '$name' in '$namespace' (timeout: ${timeout}s)..."
    if kubectl rollout status deployment/"$name" -n "$namespace" --timeout="${timeout}s" 2>/dev/null; then
        log_success "Deployment '$name' is available."
        return 0
    else
        log_warn "Deployment '$name' is not ready yet."
        return 1
    fi
}

# Wait for a daemonset to be ready
wait_for_daemonset() {
    local name="$1"
    local namespace="$2"
    local timeout="${3:-300}"
    log_info "Waiting for daemonset '$name' in '$namespace' (timeout: ${timeout}s)..."
    local end_time=$((SECONDS + timeout))
    while [ $SECONDS -lt $end_time ]; do
        local desired=$(kubectl get daemonset "$name" -n "$namespace" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
        local ready=$(kubectl get daemonset "$name" -n "$namespace" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
        if [ "$desired" -gt 0 ] && [ "$desired" = "$ready" ]; then
            log_success "DaemonSet '$name' is ready ($ready/$desired)."
            return 0
        fi
        sleep 5
    done
    log_warn "DaemonSet '$name' is not fully ready."
    return 1
}

# Retry a command with exponential backoff
retry() {
    local max_attempts="$1"
    shift
    local attempt=1
    local wait_time=5
    while [ $attempt -le "$max_attempts" ]; do
        if "$@"; then
            return 0
        fi
        log_warn "Attempt $attempt/$max_attempts failed. Retrying in ${wait_time}s..."
        sleep "$wait_time"
        attempt=$((attempt + 1))
        wait_time=$((wait_time * 2))
    done
    log_error "All $max_attempts attempts failed for: $*"
    return 1
}

# Substitute environment variables in a file
envsubst_file() {
    local input_file="$1"
    local output_file="${2:-$1}"
    if [ ! -f "$input_file" ]; then
        log_error "File not found: $input_file"
        return 1
    fi
    local tmp_file
    tmp_file=$(mktemp)
    envsubst < "$input_file" > "$tmp_file"
    mv "$tmp_file" "$output_file"
}

# Get the project root directory
get_project_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)"
    echo "$(cd "$script_dir/.." && pwd)"
}

# Load .env file if it exists
load_env() {
    local project_root
    project_root="$(get_project_root)"
    local env_file="${project_root}/.env"
    if [ -f "$env_file" ]; then
        log_info "Loading environment from $env_file"
        set -a
        # shellcheck disable=SC1090
        source "$env_file"
        set +a
    else
        log_warn "No .env file found at $env_file"
    fi
}
