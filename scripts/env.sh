#!/bin/bash
# OttoChain Environment Variables
# Source this before running other scripts

export HOST_IP="5.78.90.207"
export JARS_DIR="/opt/ottochain/jars"
export KEYS_DIR="/opt/ottochain/keys"
export DATA_DIR="/opt/ottochain/data"
export NETWORK="ottochain_ottochain"

# Key settings
export CL_KEYALIAS=${CL_KEYALIAS:-alias}
export CL_PASSWORD=${CL_PASSWORD:?Set CL_PASSWORD environment variable}
export CL_COLLATERAL=0
export CL_APP_ENV=dev

# Load peer IDs if they exist
export GL0_PEER_ID=$(cat /opt/ottochain/gl0-peer-id 2>/dev/null || echo "")
export ML0_PEER_ID=$(cat /opt/ottochain/ml0-peer-id 2>/dev/null || echo "")
export TOKEN_ID=$(cat /opt/ottochain/token-id 2>/dev/null || echo "")

# Docker image
export JAVA_IMAGE="eclipse-temurin:21-jdk"
