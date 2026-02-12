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

## Conda Environment Setup

The project applications depend on a Python 3.7 conda environment (`interfuser`). The full environment specification is exported in `configs/environment.yml`.

```bash
# 1. Install Anaconda (if not already installed)
wget https://repo.anaconda.com/archive/Anaconda3-2024.10-1-Linux-x86_64.sh
bash Anaconda3-2024.10-1-Linux-x86_64.sh -b -p $HOME/anaconda3
eval "$($HOME/anaconda3/bin/conda shell.bash hook)"
conda init

# 2. Create the environment from the exported file
conda env create -f configs/environment.yml

# 3. Activate
conda activate interfuser
```

Key packages included: PyTorch 1.9.1+cu111, torchvision 0.10.1, transformers, carla 0.9.10, opencv, timm, mmcv/mmdet, and more. See `configs/environment.yml` for the complete list.

If you encounter dependency conflicts (e.g. on a different OS/architecture), you can create a minimal environment and install the core packages manually:

```bash
conda create -n interfuser python=3.7 -y
conda activate interfuser
pip install torch==1.9.1+cu111 torchvision==0.10.1+cu111 -f https://download.pytorch.org/whl/torch_stable.html
pip install transformers datasets opencv-python-headless timm mmcv-full mmdet
```

## Quick Start

```bash
# 1. Clone the repository
git clone <repo-url> k8s-cluster-deploy
cd k8s-cluster-deploy

# 2. Configure environment
cp .env.example .env
nano .env  # Fill in your values (HF_TOKEN, etc.)

# 3. Deploy everything
sudo ./deploy.sh
```

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

## Notes

- **Single-node**: The control-plane taint is removed to allow workloads on the master node.
- **HAMi GPU sharing**: Koordinator + HAMi enables GPU fractional scheduling via `koordinator.sh/gpu-core` and `koordinator.sh/gpu-memory-ratio` resources.
- **Chinese mirrors**: Koordinator uses `registry.cn-beijing.aliyuncs.com` by default. Change `imageRepositoryHost` in `helm-values/koordinator-values.yaml` if needed.
- **NVIDIA MPS**: Multi-Process Service is configured via systemd for persistent GPU sharing.
- **Akash dynamic namespaces**: Akash Provider automatically manages tenant namespaces at runtime.
