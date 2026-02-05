#!/bin/bash
# OttoChain Cluster Inventory
# Source this file to get cluster configuration

# Machine IPs
export NODE1_IP="5.78.90.207"      # Genesis node
export NODE2_IP="5.78.113.25"      # Validator 1
export NODE3_IP="5.78.107.77"      # Validator 2
export SERVICES_IP="5.78.121.248"  # Services (bridge, indexer, explorer)

# All metagraph nodes
export NODES=("$NODE1_IP" "$NODE2_IP" "$NODE3_IP")

# SSH configuration
export SSH_KEY="${SSH_KEY:-~/.ssh/hetzner_ottobot}"
export SSH_USER="${SSH_USER:-root}"
export SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

# Remote paths
export REMOTE_DIR="/opt/ottochain"
export REMOTE_JARS="$REMOTE_DIR/jars"
export REMOTE_KEYS="$REMOTE_DIR/keys"
export REMOTE_DATA="$REMOTE_DIR/data"
export REMOTE_SCRIPTS="$REMOTE_DIR/scripts"

# Docker
export JAVA_IMAGE="eclipse-temurin:21-jdk"
export NETWORK="ottochain"

# Port assignments
export GL0_PUBLIC=9000
export GL0_P2P=9001
export GL0_CLI=9002

export GL1_PUBLIC=9100
export GL1_P2P=9101
export GL1_CLI=9102

export ML0_PUBLIC=9200
export ML0_P2P=9201
export ML0_CLI=9202

export CL1_PUBLIC=9300
export CL1_P2P=9301
export CL1_CLI=9302

export DL1_PUBLIC=9400
export DL1_P2P=9401
export DL1_CLI=9402

# Helper functions
ssh_node() {
    local node_ip=$1
    shift
    ssh $SSH_OPTS ${SSH_USER}@${node_ip} "$@"
}

scp_to_node() {
    local node_ip=$1
    local src=$2
    local dst=$3
    scp $SSH_OPTS "$src" ${SSH_USER}@${node_ip}:"$dst"
}

for_each_node() {
    local cmd=$1
    for ip in "${NODES[@]}"; do
        echo "=== Node $ip ==="
        ssh_node "$ip" "$cmd"
    done
}
