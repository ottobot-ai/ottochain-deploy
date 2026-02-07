#!/bin/bash
# OttoChain Cluster Inventory
# Source this file to get node IPs and other config

# Hetzner nodes
export NODE1_IP="${NODE1_IP:-${NODE1_IP}}"     # Genesis node
export NODE2_IP="${NODE2_IP:-${NODE2_IP}}"     # Validator 2
export NODE3_IP="${NODE3_IP:-${NODE3_IP}}"     # Validator 3
export SERVICES_IP="${SERVICES_IP:-${SERVICES_IP}}"  # Services (indexer, explorer, monitor)

# SSH config
export SSH_KEY="${SSH_KEY:-$HOME/.ssh/hetzner_ottobot}"
export SSH_USER="${SSH_USER:-root}"

# Tessellation version
export TESSELLATION_VERSION="${TESSELLATION_VERSION:-v4.0.0-rc.2}"

# Remote paths
export REMOTE_DIR="${REMOTE_DIR:-/opt/ottochain}"
export SERVICES_DIR="${SERVICES_DIR:-/opt/ottochain-services}"

# Array of metagraph nodes
export NODES=("$NODE1_IP" "$NODE2_IP" "$NODE3_IP")
