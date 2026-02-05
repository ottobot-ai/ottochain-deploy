#!/bin/bash
# OttoChain Cluster Inventory
# Source this file to get node IPs and other config

# Hetzner nodes
export NODE1_IP="${NODE1_IP:-5.78.90.207}"     # Genesis node
export NODE2_IP="${NODE2_IP:-5.78.113.25}"     # Validator 2
export NODE3_IP="${NODE3_IP:-5.78.107.77}"     # Validator 3
export SERVICES_IP="${SERVICES_IP:-5.78.121.248}"  # Services (indexer, explorer, monitor)

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
