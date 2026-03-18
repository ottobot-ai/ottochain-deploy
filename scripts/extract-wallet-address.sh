#!/usr/bin/env bash
# Extract wallet address from a p12 keystore using cl-wallet
# Usage: extract-wallet-address.sh <keystore_path> <password> [alias]

set -euo pipefail

KEYSTORE="${1:?Usage: extract-wallet-address.sh <keystore_path> <password> [alias]}"
PASSWORD="${2:?Password required}"
ALIAS="${3:-alias}"

CL_WALLET="/opt/ottochain/cl-wallet.jar"

# Download cl-wallet if missing (version from versions.yaml or fallback)
if [ ! -f "$CL_WALLET" ]; then
  TESS_VERSION="${TESSELLATION_VERSION:-4.0.0-rc.10}"
  curl -sL -o "$CL_WALLET" \
    "https://github.com/Constellation-Labs/tessellation/releases/download/v${TESS_VERSION}/cl-wallet.jar"
fi

# Extract address (grep the DAG address from output)
CL_KEYSTORE="$KEYSTORE" CL_KEYALIAS="$ALIAS" CL_PASSWORD="$PASSWORD" \
  java -jar "$CL_WALLET" show-address 2>&1 | grep -oP 'DAG[a-zA-Z0-9]+' | head -1
