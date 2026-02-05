#!/bin/bash
# Start the OttoChain Docker cluster across all nodes
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../inventory.sh" 2>/dev/null || true

SSH_KEY="${SSH_KEY:-$HOME/.ssh/hetzner_ottobot}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $SSH_KEY"
REMOTE_DIR="/opt/ottochain"

NODE1_IP="${NODE1_IP:-5.78.90.207}"
NODE2_IP="${NODE2_IP:-5.78.113.25}"
NODE3_IP="${NODE3_IP:-5.78.107.77}"

start_node() {
    local node_num=$1
    local node_ip=$2
    
    echo "=== Starting Node $node_num ($node_ip) ==="
    ssh $SSH_OPTS root@$node_ip "cd $REMOTE_DIR && docker compose up -d"
    echo "✓ Node $node_num started"
}

wait_for_layer() {
    local node_ip=$1
    local port=$2
    local layer=$3
    local max_attempts=30
    local attempt=0
    
    echo -n "Waiting for $layer on $node_ip:$port..."
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -sf "http://$node_ip:$port/node/info" > /dev/null 2>&1; then
            echo " Ready!"
            return 0
        fi
        echo -n "."
        sleep 5
        ((attempt++))
    done
    echo " Timeout!"
    return 1
}

echo "============================================"
echo "Starting OttoChain Cluster"
echo "============================================"

# Start genesis node first
start_node 1 $NODE1_IP

# Wait for genesis GL0 to be ready
wait_for_layer $NODE1_IP 9000 "GL0"
wait_for_layer $NODE1_IP 9200 "ML0"

# Start joining nodes
echo ""
echo "Starting joining nodes..."
start_node 2 $NODE2_IP &
start_node 3 $NODE3_IP &
wait

echo ""
echo "============================================"
echo "Cluster startup initiated!"
echo "============================================"
echo ""
echo "Check cluster status with: $SCRIPT_DIR/status-cluster.sh"
