#!/usr/bin/env bash
# 00-prerequisites.sh - System dependency checks and preparation
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

log_info "=== Step 0: Checking prerequisites ==="

# Check running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root (or with sudo)."
    exit 1
fi

# Check Ubuntu version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    log_info "OS: $PRETTY_NAME"
    if [[ "$ID" != "ubuntu" ]]; then
        log_warn "This script is designed for Ubuntu. Your OS ($ID) may not be fully supported."
    fi
    if [[ "$VERSION_ID" != "22.04" && "$VERSION_ID" != "24.04" ]]; then
        log_warn "Tested on Ubuntu 22.04/24.04. Your version ($VERSION_ID) may work but is untested."
    fi
else
    log_warn "Cannot detect OS version."
fi

# Disable swap
log_info "Disabling swap..."
swapoff -a || true
# Comment out swap entries in fstab
sed -i '/\sswap\s/s/^/#/' /etc/fstab
log_success "Swap disabled."

# Load required kernel modules
log_info "Loading kernel modules..."
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter
log_success "Kernel modules loaded."

# Set sysctl parameters
log_info "Configuring sysctl for Kubernetes..."
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system >/dev/null 2>&1
log_success "Sysctl parameters configured."

# Verify kernel module settings
log_info "Verifying kernel parameters..."
if [ "$(sysctl -n net.bridge.bridge-nf-call-iptables)" != "1" ]; then
    log_error "net.bridge.bridge-nf-call-iptables is not set to 1"
    exit 1
fi
if [ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]; then
    log_error "net.ipv4.ip_forward is not set to 1"
    exit 1
fi
log_success "Kernel parameters verified."

# Install basic dependencies
log_info "Installing basic dependencies..."
apt-get update -qq
apt-get install -y -qq \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    jq \
    gettext-base \
    socat \
    conntrack \
    ipset \
    >/dev/null 2>&1
log_success "Basic dependencies installed."

# Check hardware
log_info "Checking hardware..."
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
CPU_COUNT=$(nproc)
log_info "  CPU cores: $CPU_COUNT"
log_info "  Total memory: ${TOTAL_MEM}MB"

if [ "$TOTAL_MEM" -lt 4096 ]; then
    log_warn "Less than 4GB RAM detected. Kubernetes may not run reliably."
fi
if [ "$CPU_COUNT" -lt 2 ]; then
    log_warn "Less than 2 CPU cores detected. Kubernetes requires at least 2 cores."
fi

# Check for NVIDIA GPU
if lspci | grep -qi nvidia; then
    log_success "NVIDIA GPU detected."
else
    log_warn "No NVIDIA GPU detected. GPU-related components may not work."
fi

log_success "=== Prerequisites check completed ==="
