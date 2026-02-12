#!/usr/bin/env bash
# 04-install-nvidia.sh - Install NVIDIA Driver, CUDA Toolkit, and Container Toolkit
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${SCRIPT_DIR}/utils.sh"

NVIDIA_DRIVER_VERSION="560"

log_info "=== Step 4: Installing NVIDIA GPU stack ==="

# Check for NVIDIA GPU
if ! lspci | grep -qi nvidia; then
    log_error "No NVIDIA GPU detected. Skipping NVIDIA installation."
    log_error "GPU-dependent components will not function."
    exit 1
fi

# ---- NVIDIA Driver ----
if check_command nvidia-smi; then
    DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
    log_info "NVIDIA driver is already installed (version: $DRIVER_VER)."
else
    log_info "Installing NVIDIA driver ${NVIDIA_DRIVER_VERSION}..."
    apt-get update -qq
    apt-get install -y -qq "nvidia-driver-${NVIDIA_DRIVER_VERSION}" >/dev/null 2>&1
    log_success "NVIDIA driver installed. A reboot may be required."
fi

# Verify driver
if nvidia-smi &>/dev/null; then
    log_success "NVIDIA driver is functional."
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
else
    log_error "nvidia-smi failed. You may need to reboot."
    log_error "After reboot, re-run: sudo bash scripts/04-install-nvidia.sh"
    exit 1
fi

# ---- CUDA Toolkit ----
if check_command nvcc; then
    CUDA_VER=$(nvcc --version 2>/dev/null | grep "release" | awk '{print $5}' | tr -d ',' || echo "unknown")
    log_info "CUDA Toolkit is already installed (version: $CUDA_VER)."
else
    log_info "Installing CUDA Toolkit..."
    apt-get install -y -qq nvidia-cuda-toolkit >/dev/null 2>&1 || true
    log_success "CUDA Toolkit installed."
fi

# ---- NVIDIA Container Toolkit ----
if check_command nvidia-ctk; then
    log_info "NVIDIA Container Toolkit is already installed."
else
    log_info "Installing NVIDIA Container Toolkit..."

    # Add NVIDIA Container Toolkit repository
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

    apt-get update -qq
    apt-get install -y -qq nvidia-container-toolkit >/dev/null 2>&1
    log_success "NVIDIA Container Toolkit installed."
fi

# Configure containerd for NVIDIA runtime
log_info "Configuring containerd NVIDIA runtime..."
# Our containerd config already includes the NVIDIA runtime
# Just make sure the config is in place
if [ -f "${PROJECT_ROOT}/configs/containerd-config.toml" ]; then
    cp "${PROJECT_ROOT}/configs/containerd-config.toml" /etc/containerd/config.toml
    systemctl restart containerd
    sleep 2
fi

# Create NVIDIA RuntimeClass for Kubernetes
log_info "Creating NVIDIA RuntimeClass..."
kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nvidia
handler: nvidia
EOF
log_success "NVIDIA RuntimeClass created."

# Configure and start NVIDIA MPS (Multi-Process Service)
log_info "Configuring NVIDIA MPS..."
if ! pgrep -x "nvidia-cuda-mps" &>/dev/null; then
    # Set MPS environment
    export CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps
    export CUDA_MPS_LOG_DIRECTORY=/tmp/nvidia-log
    mkdir -p "$CUDA_MPS_PIPE_DIRECTORY" "$CUDA_MPS_LOG_DIRECTORY"

    # Start MPS daemon
    nvidia-cuda-mps-control -d 2>/dev/null || true
    log_success "NVIDIA MPS daemon started."
else
    log_info "NVIDIA MPS daemon is already running."
fi

# Create systemd service for MPS persistence
cat > /etc/systemd/system/nvidia-mps.service <<EOF
[Unit]
Description=NVIDIA CUDA MPS Server
After=nvidia-persistenced.service

[Service]
Type=forking
Environment=CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps
Environment=CUDA_MPS_LOG_DIRECTORY=/tmp/nvidia-log
ExecStartPre=/bin/mkdir -p /tmp/nvidia-mps /tmp/nvidia-log
ExecStart=/usr/bin/nvidia-cuda-mps-control -d
ExecStop=/bin/bash -c 'echo quit | /usr/bin/nvidia-cuda-mps-control'
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nvidia-mps.service
systemctl start nvidia-mps.service 2>/dev/null || true

log_success "=== NVIDIA GPU stack installation completed ==="
