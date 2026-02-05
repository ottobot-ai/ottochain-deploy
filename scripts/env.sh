#!/bin/bash
# OttoChain Environment Variables
# Source this before running other scripts

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load local secrets (required)
if [ -f "$SCRIPT_DIR/.env.local" ]; then
    source "$SCRIPT_DIR/.env.local"
elif [ -f "/opt/ottochain/.env.local" ]; then
    source "/opt/ottochain/.env.local"
else
    echo "ERROR: No .env.local found!"
    echo ""
    echo "Create one from template:"
    echo "  cp scripts/.env.example scripts/.env.local"
    echo "  # Edit .env.local with your values"
    echo ""
    echo "Or on the server:"
    echo "  cp /opt/ottochain/.env.example /opt/ottochain/.env.local"
    exit 1
fi

# Validate required vars
: "${CL_PASSWORD:?CL_PASSWORD not set in .env.local}"
: "${HOST_IP:?HOST_IP not set in .env.local}"

# Directories
export JARS_DIR="${JARS_DIR:-/opt/ottochain/jars}"
export KEYS_DIR="${KEYS_DIR:-/opt/ottochain/keys}"
export DATA_DIR="${DATA_DIR:-/opt/ottochain/data}"
export NETWORK="${NETWORK:-ottochain_ottochain}"

# Key settings
export CL_KEYALIAS="${CL_KEYALIAS:-alias}"
export CL_COLLATERAL="${CL_COLLATERAL:-0}"
export CL_APP_ENV="${CL_APP_ENV:-dev}"

# Load dynamic peer IDs if they exist
export GL0_PEER_ID=$(cat /opt/ottochain/gl0-peer-id 2>/dev/null || echo "")
export ML0_PEER_ID=$(cat /opt/ottochain/ml0-peer-id 2>/dev/null || echo "")
export TOKEN_ID=$(cat /opt/ottochain/token-id 2>/dev/null || echo "")

# Docker image
export JAVA_IMAGE="${JAVA_IMAGE:-eclipse-temurin:21-jdk}"

echo "Environment loaded: HOST_IP=$HOST_IP, CL_KEYALIAS=$CL_KEYALIAS"
