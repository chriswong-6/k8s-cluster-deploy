#!/usr/bin/env bash
# install-akash-cli.sh - Download akash CLI v1.1.0 for wallet and chain operations
# The Provider service runs inside K8s Pods via Helm — this CLI is only needed
# for pre-deployment setup (wallet creation, provider registration, certificates).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="${PROJECT_ROOT}/bin"

AKASH_VERSION="1.1.0"
AKASH_URL="https://github.com/akash-network/node/releases/download/v${AKASH_VERSION}/akash_linux_amd64.zip"

mkdir -p "$BIN_DIR"

if [ -x "$BIN_DIR/akash" ]; then
    CURRENT_VER=$("$BIN_DIR/akash" version 2>/dev/null || echo "unknown")
    echo "akash CLI already installed (version: $CURRENT_VER). Skipping."
    exit 0
fi

echo "Downloading akash CLI v${AKASH_VERSION}..."
curl -sL "$AKASH_URL" -o /tmp/akash_linux_amd64.zip
unzip -o /tmp/akash_linux_amd64.zip -d "$BIN_DIR/"
chmod +x "$BIN_DIR/akash"
rm -f /tmp/akash_linux_amd64.zip

echo "akash CLI v${AKASH_VERSION} installed to ${BIN_DIR}/akash"
"$BIN_DIR/akash" version
