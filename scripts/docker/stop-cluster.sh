#!/bin/bash
# Stop the OttoChain Docker cluster across all nodes
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../inventory.sh" 2>/dev/null || true

SSH_KEY="${SSH_KEY:-$HOME/.ssh/hetzner_ottobot}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $SSH_KEY"
REMOTE_DIR="/opt/ottochain"

NODE1_IP="${NODE1_IP:-5.78.90.207}"
NODE2_IP="${NODE2_IP:-5.78.113.25}"
NODE3_IP="${NODE3_IP:-5.78.107.77}"

stop_node() {
    local node_num=$1
    local node_ip=$2
    
    echo "=== Stopping Node $node_num ($node_ip) ==="
    ssh $SSH_OPTS root@$node_ip "cd $REMOTE_DIR && docker compose down" 2>/dev/null || true
    echo "✓ Node $node_num stopped"
}

echo "============================================"
echo "Stopping OttoChain Cluster"
echo "============================================"

# Stop all nodes in parallel
stop_node 1 $NODE1_IP &
stop_node 2 $NODE2_IP &
stop_node 3 $NODE3_IP &
wait

echo ""
echo "✓ All nodes stopped"
