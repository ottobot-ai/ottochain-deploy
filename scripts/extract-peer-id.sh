#!/usr/bin/env bash
# Extract peer ID from a p12 keystore using cl-wallet
# Usage: extract-peer-id.sh <keystore_path> <password> [alias]
#
# Requires: java, cl-wallet.jar at /opt/ottochain/cl-wallet.jar
# Downloads cl-wallet.jar if missing.

set -euo pipefail

KEYSTORE="${1:?Usage: extract-peer-id.sh <keystore_path> <password> [alias]}"
PASSWORD="${2:?Password required}"
ALIAS="${3:-alias}"

CL_WALLET="/opt/ottochain/cl-wallet.jar"

# Download cl-wallet if missing
if [ ! -f "$CL_WALLET" ]; then
  curl -sL -o "$CL_WALLET" \
    https://github.com/Constellation-Labs/tessellation/releases/download/v4.0.0-rc.2/cl-wallet.jar
fi

# Extract peer ID
CL_KEYSTORE="$KEYSTORE" CL_KEYALIAS="$ALIAS" CL_PASSWORD="$PASSWORD" \
  java -jar "$CL_WALLET" show-id 2>/dev/null
