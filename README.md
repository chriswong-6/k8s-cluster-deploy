# K8s Single-Node GPU Cluster - One-Click Deploy

Deploy a complete Kubernetes single-node cluster with GPU scheduling, Serverless platform, decentralized computing, and monitoring.

## Components

| Component | Version | Description |
|-----------|---------|-------------|
| Kubernetes | v1.28.15 | kubeadm + containerd |
| Calico CNI | v3.27.2 | Pod networking (IPIP mode) |
| NVIDIA Driver | 560.35.03 | GPU driver + CUDA 12.6 |
| NVIDIA Container Toolkit | latest | GPU container runtime |
| Koordinator | v1.6.0 | Advanced scheduling + HAMi GPU sharing |
| OpenFaaS | 14.2.103 | Serverless function platform |
| kube-prometheus-stack | 77.9.1 | Prometheus + Grafana monitoring |
| ingress-nginx | 4.8.3 | Ingress controller |
| Akash Provider | 14.0.6 | Decentralized compute (optional) |
| local-path-provisioner | v0.0.26 | Local storage provisioner |
| NeMo Operator | CRDs only | NVIDIA NeMo (optional) |

## Prerequisites

- **OS**: Ubuntu 22.04 or 24.04 LTS
- **GPU**: NVIDIA RTX 4090 (or compatible)
- **RAM**: 16GB+ recommended
- **CPU**: 4+ cores recommended
- **Disk**: 100GB+ free space
- **Network**: Internet access for pulling images

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/chriswong-6/k8s-cluster-deploy.git
cd k8s-cluster-deploy

# 2. Configure environment variables
cp .env.example .env
nano .env  # Fill in your values (HF_TOKEN, etc.)

# 3. Install Anaconda (if not already installed)
wget https://repo.anaconda.com/archive/Anaconda3-2024.10-1-Linux-x86_64.sh
bash Anaconda3-2024.10-1-Linux-x86_64.sh -b -p $HOME/anaconda3
eval "$($HOME/anaconda3/bin/conda shell.bash hook)"
conda init

# 4. Create and activate conda environment
conda env create -f configs/environment.yml
conda activate cluster

# 5. Install CARLA (not available on PyPI, installed separately)
bash configs/setup_carla.sh
easy_install carla/PythonAPI/carla/dist/carla-0.9.10-py3.7-linux-x86_64.egg

# 6. Deploy K8s cluster
sudo ./deploy.sh
```

Key packages included: PyTorch 1.13.1, torchvision 0.14.1, carla 0.9.10, opencv, and more. See `configs/environment.yml` for the complete list.

If you encounter dependency conflicts (e.g. on a different OS/architecture), you can create a minimal environment with PTX-compatible CUDA 11.1 packages:

```bash
conda create -n cluster python=3.7 -y
conda activate cluster
pip install torch==1.9.1+cu111 torchvision==0.10.1+cu111 -f https://download.pytorch.org/whl/torch_stable.html
pip install transformers datasets opencv-python-headless timm mmcv-full mmdet
```

> **Note**: The `cu111` builds use PTX JIT compilation, allowing them to run on newer GPUs (e.g. RTX 4090 with CUDA 12.6) via NVIDIA Forward Compatibility. See [CUDA Forward Compatibility](#cuda-forward-compatibility-ptx-jit) section below.

## Configuration

Copy `.env.example` to `.env` and configure:

| Variable | Required | Description |
|----------|----------|-------------|
| `HF_TOKEN` | Yes* | HuggingFace token for model downloads |
| `GRAFANA_ADMIN_PASSWORD` | No | Grafana password (default: prom-operator) |
| `DEPLOY_AKASH` | No | Set `true` to deploy Akash Provider |
| `AKASH_KEY` | If Akash | Base64-encoded Akash private key |
| `AKASH_KEY_SECRET` | If Akash | Base64-encoded key secret |
| `AKASH_DOMAIN` | If Akash | Provider domain |
| `AKASH_NODE` | If Akash | Chain node URL |
| `AKASH_FROM` | If Akash | Wallet address |
| `AKASH_EMAIL` | If Akash | Contact email |
| `NGC_API_KEY` | No | NVIDIA NGC API key |
| `DEPLOY_NEMO` | No | Set `true` to install NeMo CRDs |

*Required for fastapi-llama to function properly.

## Deploy Options

```bash
# Full deployment (from bare metal)
sudo ./deploy.sh

# Skip K8s install (if Kubernetes is already running)
sudo ./deploy.sh --skip-k8s

# Skip NVIDIA driver install (if drivers are already installed)
sudo ./deploy.sh --skip-nvidia

# Deploy only application layer (K8s + components assumed ready)
sudo ./deploy.sh --apps-only
```

## Local Image: fastapi-llama

The `fastapi-llama:abc` image is built locally and NOT available from any registry. Before deploying, you must:

1. **Build locally** (if Dockerfile is available):
   ```bash
   docker build -t fastapi-llama:abc /path/to/source
   docker save fastapi-llama:abc | sudo ctr -n k8s.io images import -
   ```

2. **Import from archive**:
   ```bash
   sudo ctr -n k8s.io images import fastapi-llama.tar
   ```

3. **Use a registry**: Update `manifests/apps/fastapi-llama.yaml` with your registry URL.

## Uninstall

```bash
# Remove applications only
sudo ./uninstall.sh --apps-only

# Remove all Helm components
sudo ./uninstall.sh

# Full teardown (including kubeadm reset)
sudo ./uninstall.sh --full
```

## Verification

After deployment, the verification script runs automatically. To re-run:

```bash
bash scripts/08-verify.sh
```

Expected results:
- All system pods Running
- `nvidia-smi` functional
- OpenFaaS UI at http://localhost:31112/ui
- Grafana via `kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80`
- fastapi-llama at http://localhost:30800

## Repository Structure

```
k8s-cluster-deploy/
├── deploy.sh                 # Main deployment script
├── uninstall.sh              # Uninstall script
├── .env.example              # Environment template
├── scripts/
│   ├── 00-prerequisites.sh   # System checks
│   ├── 01-install-containerd.sh
│   ├── 02-install-kubernetes.sh
│   ├── 03-install-calico.sh
│   ├── 04-install-nvidia.sh
│   ├── 05-install-helm.sh
│   ├── 06-deploy-components.sh
│   ├── 07-deploy-apps.sh
│   ├── 08-verify.sh
│   └── utils.sh
├── helm-values/              # Helm chart values
├── manifests/                # K8s manifests
│   ├── apps/                 # Application manifests
│   ├── nemo-crds/            # NeMo CRDs
│   ├── namespaces.yaml
│   ├── storage-classes.yaml
│   └── calico-ippool.yaml
└── configs/                  # System configs
    ├── kubeadm-config.yaml
    ├── containerd-config.toml
    ├── environment.yml       # Conda environment
    └── calico.yaml
```

## CUDA Forward Compatibility (PTX JIT)

The host runs NVIDIA Driver 560.35.03 with CUDA 12.6, but some containers (e.g. `modelproc`) use older CUDA versions (CUDA 11.8, PyTorch built with CUDA 11.7). This is resolved using **NVIDIA CUDA Forward Compatibility** via PTX JIT compilation.

### How it works

The container image includes the `cuda-compat-11-8` package, which installs compatibility libraries under `/usr/local/cuda-11.8/compat/`:

```
/usr/local/cuda-11.8/compat/
├── libcuda.so, libcuda.so.1, libcuda.so.520.61.05
├── libcudadebugger.so.1, libcudadebugger.so.520.61.05
├── libnvidia-nvvm.so, libnvidia-nvvm.so.4, libnvidia-nvvm.so.520.61.05
└── libnvidia-ptxjitcompiler.so.1, libnvidia-ptxjitcompiler.so.520.61.05
```

The `libnvidia-ptxjitcompiler.so` library enables PTX (Parallel Thread Execution) JIT compilation, allowing older CUDA toolkit code to be compiled at runtime for the newer GPU architecture (Ada Lovelace / sm_89 on RTX 4090).

### Building compatible container images

When building images that need to run older CUDA on this host, ensure the `cuda-compat` package is installed in the Dockerfile:

```dockerfile
# Example: CUDA 11.8 base image with forward compatibility
FROM nvidia/cuda:11.8.0-runtime-ubuntu20.04

# Install CUDA forward compatibility package
RUN apt-get update && apt-get install -y cuda-compat-11-8 && rm -rf /var/lib/apt/lists/*

# Ensure the compat libraries are on LD_LIBRARY_PATH
ENV LD_LIBRARY_PATH=/usr/local/cuda-11.8/compat:${LD_LIBRARY_PATH}
```

### Key environment variables in containers

The following env vars are set in the deployment manifests to ensure proper CUDA operation:

| Variable | Value | Purpose |
|----------|-------|---------|
| `NVIDIA_VISIBLE_DEVICES` | `all` | Expose all GPUs to container |
| `NVIDIA_DRIVER_CAPABILITIES` | `compute,utility` | Enable compute + nvidia-smi |
| `CUDA_HOME` | `/usr/local/cuda-XX.X` | CUDA toolkit path |
| `LD_LIBRARY_PATH` | `/usr/local/cuda-XX.X/lib64:...` | Library search path (compat libs loaded first) |

### Host requirements

- NVIDIA Driver >= 520 (for CUDA 11.8 compat) — current host has 560.35.03
- `nvidia-container-toolkit` configured with `disable-require = false` (default)
- `nvidia-persistenced` service active for stable GPU state

## Notes

- **Single-node**: The control-plane taint is removed to allow workloads on the master node.
- **HAMi GPU sharing**: Koordinator + HAMi enables GPU fractional scheduling via `koordinator.sh/gpu-core` and `koordinator.sh/gpu-memory-ratio` resources.
- **Chinese mirrors**: Koordinator uses `registry.cn-beijing.aliyuncs.com` by default. Change `imageRepositoryHost` in `helm-values/koordinator-values.yaml` if needed.
- **NVIDIA MPS**: Multi-Process Service is configured via systemd for persistent GPU sharing.
- **Akash dynamic namespaces**: Akash Provider automatically manages tenant namespaces at runtime.
