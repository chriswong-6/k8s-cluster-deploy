#!/usr/bin/env bash
# 01-install-containerd.sh - Install and configure containerd
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${SCRIPT_DIR}/utils.sh"

log_info "=== Step 1: Installing containerd ==="

if check_command containerd; then
    INSTALLED_VERSION=$(containerd --version 2>/dev/null | awk '{print $3}' || echo "unknown")
    log_info "containerd is already installed (version: $INSTALLED_VERSION)."
    log_info "Skipping installation, will update configuration."
else
    # Install containerd from Docker's official repository
    log_info "Adding Docker repository for containerd..."

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -qq
    log_info "Installing containerd.io..."
    apt-get install -y -qq containerd.io >/dev/null 2>&1
    log_success "containerd installed."
fi

# Configure containerd
log_info "Configuring containerd..."
mkdir -p /etc/containerd

# Copy our pre-configured containerd config with NVIDIA runtime support
cp "${PROJECT_ROOT}/configs/containerd-config.toml" /etc/containerd/config.toml

# Restart containerd to apply config
systemctl daemon-reload
systemctl enable containerd
systemctl restart containerd

# Verify containerd is running
sleep 2
if systemctl is-active --quiet containerd; then
    log_success "containerd is running."
else
    log_error "containerd failed to start. Check: journalctl -u containerd"
    exit 1
fi

log_success "=== containerd installation completed ==="
