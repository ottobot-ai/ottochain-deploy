#!/bin/bash
# OttoChain Rolling Layer Restart
# Restarts a layer one node at a time, waiting for Ready between
# Usage: ./restart-layer.sh <layer> [--force]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/.env" 2>/dev/null || true

# Node IPs
NODE1="${NODE1_IP:-5.78.90.207}"
NODE2="${NODE2_IP:-5.78.113.25}"
NODE3="${NODE3_IP:-5.78.107.77}"
NODES=("$NODE1" "$NODE2" "$NODE3")

# SSH key
SSH_KEY="${SSH_KEY:-$HOME/.ssh/hetzner_ottobot}"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10"

# Layer -> container name and port
declare -A LAYER_CONTAINERS=(
    ["gl0"]="gl0"
    ["gl1"]="gl1"
    ["ml0"]="ml0"
    ["cl1"]="cl1"
    ["dl1"]="dl1"
)

declare -A LAYER_PORTS=(
    ["gl0"]=9000
    ["gl1"]=9100
    ["ml0"]=9200
    ["cl1"]=9300
    ["dl1"]=9400
)

LAYER="${1:-}"
FORCE=false
[[ "$2" == "--force" ]] && FORCE=true

if [ -z "$LAYER" ] || [ -z "${LAYER_CONTAINERS[$LAYER]}" ]; then
    echo "Usage: $0 <layer> [--force]"
    echo "Layers: gl0, gl1, ml0, cl1, dl1"
    exit 1
fi

CONTAINER="${LAYER_CONTAINERS[$LAYER]}"
PORT="${LAYER_PORTS[$LAYER]}"

wait_for_ready_or_join() {
    local host=$1
    local port=$2
    local cli_port=$((port + 2))  # CLI port is public port + 2
    local timeout=120
    local elapsed=0
    
    echo "  Waiting for $CONTAINER on $host to be Ready or ReadyToJoin..."
    while [ $elapsed -lt $timeout ]; do
        state=$(curl -s --connect-timeout 5 "http://$host:$port/cluster/info" 2>/dev/null | jq -r '.[0].state // "UNKNOWN"')
        
        if [ "$state" = "Ready" ]; then
            echo "  ✓ $CONTAINER on $host is Ready"
            return 0
        fi
        
        if [ "$state" = "ReadyToJoin" ]; then
            echo "  → $CONTAINER on $host is ReadyToJoin, triggering cluster join..."
            # Get peer ID from node1 (genesis node)
            local peer_id=$(curl -s --connect-timeout 5 "http://$NODE1:$port/node/info" | jq -r '.id // empty')
            if [ -n "$peer_id" ] && [ "$host" != "$NODE1" ]; then
                local p2p_port=$((port + 1))
                ssh $SSH_OPTS "root@$host" "curl -sf -X POST http://127.0.0.1:$cli_port/cluster/join \
                    -H 'Content-Type: application/json' \
                    -d '{\"id\": \"$peer_id\", \"ip\": \"$NODE1\", \"p2pPort\": $p2p_port}'" 2>/dev/null || true
                sleep 5
                continue
            fi
        fi
        
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  ... $state (${elapsed}s)"
    done
    
    echo "  ✗ Timeout waiting for Ready on $host"
    return 1
}

check_cluster_size() {
    local host=$1
    local port=$2
    
    size=$(curl -s --connect-timeout 5 "http://$host:$port/cluster/info" 2>/dev/null | jq 'length')
    echo "${size:-0}"
}

echo "=== Rolling restart of $LAYER ==="
echo "Container: $CONTAINER"
echo "Port: $PORT"
echo "Nodes: ${NODES[*]}"
echo ""

# Pre-flight check
if ! $FORCE; then
    echo "Pre-flight check..."
    for node in "${NODES[@]}"; do
        state=$(curl -s --connect-timeout 5 "http://$node:$PORT/cluster/info" 2>/dev/null | jq -r '.[0].state // "UNKNOWN"')
        if [ "$state" != "Ready" ] && [ "$state" != "ReadyToJoin" ]; then
            echo "Warning: $node $CONTAINER is in state '$state'"
            read -p "Continue anyway? [y/N] " -n 1 -r
            echo
            [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
        fi
    done
fi

# Rolling restart
for i in "${!NODES[@]}"; do
    node="${NODES[$i]}"
    echo ""
    echo "[Node $((i+1))/3] Restarting $CONTAINER on $node..."
    
    # Restart container
    ssh $SSH_OPTS "root@$node" "docker restart $CONTAINER" || {
        echo "Error: Failed to restart on $node"
        exit 1
    }
    
    # Wait for Ready (or ReadyToJoin + auto-join)
    sleep 5
    if ! wait_for_ready_or_join "$node" "$PORT"; then
        echo "Error: Node failed to become Ready"
        if ! $FORCE; then
            read -p "Continue to next node? [y/N] " -n 1 -r
            echo
            [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
        fi
    fi
    
    # Check cluster size before continuing
    size=$(check_cluster_size "$node" "$PORT")
    echo "  Cluster size: $size"
    
    # Brief pause between nodes
    if [ $i -lt $((${#NODES[@]} - 1)) ]; then
        echo "  Waiting 10s before next node..."
        sleep 10
    fi
done

echo ""
echo "=== Restart complete ==="

# Final status
echo ""
echo "Final cluster status:"
for node in "${NODES[@]}"; do
    state=$(curl -s --connect-timeout 5 "http://$node:$PORT/cluster/info" 2>/dev/null | jq -r '.[0].state // "UNKNOWN"')
    size=$(check_cluster_size "$node" "$PORT")
    echo "  $node: $state ($size nodes)"
done
