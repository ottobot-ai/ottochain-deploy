#!/bin/bash
# Stop the entire OttoChain distributed cluster
# Usage: ./scripts/distributed/stop-cluster.sh [--clean]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../inventory.sh"

CLEAN=false
if [ "$1" == "--clean" ]; then
    CLEAN=true
    echo "⚠️  CLEAN MODE: Will remove all data"
fi

echo "============================================"
echo "     OttoChain Distributed Cluster Stop"
echo "============================================"
echo ""

LAYERS=(dl1 cl1 ml0 gl1 gl0)

for NODE_IP in "${NODES[@]}"; do
    echo "=== Stopping $NODE_IP ==="
    
    for LAYER in "${LAYERS[@]}"; do
        echo "  Stopping $LAYER..."
        ssh_node "$NODE_IP" "docker rm -f $LAYER 2>/dev/null || true"
    done
    
    if [ "$CLEAN" = true ]; then
        echo "  Cleaning data..."
        ssh_node "$NODE_IP" "rm -rf $REMOTE_DATA/* 2>/dev/null || true"
        ssh_node "$NODE_IP" "rm -f $REMOTE_DIR/genesis/genesis.csv 2>/dev/null || true"
    fi
    
    echo "  ✓ Done"
done

# Clear cluster state
rm -f "$SCRIPT_DIR/../../.cluster-state"

echo ""
echo "============================================"
echo "     Cluster Stopped"
echo "============================================"
