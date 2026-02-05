#!/bin/bash
# Check OttoChain distributed cluster status
# Usage: ./scripts/distributed/status-cluster.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../inventory.sh"

echo "============================================"
echo "     OttoChain Distributed Cluster Status"
echo "============================================"
echo ""

LAYERS=(gl0 gl1 ml0 cl1 dl1)
PORTS=($GL0_PUBLIC $GL1_PUBLIC $ML0_PUBLIC $CL1_PUBLIC $DL1_PUBLIC)

# Header
printf "%-8s" "Layer"
for NODE_IP in "${NODES[@]}"; do
    printf "%-18s" "$NODE_IP"
done
echo ""
printf "%-8s" "-----"
for NODE_IP in "${NODES[@]}"; do
    printf "%-18s" "-----------------"
done
echo ""

# Check each layer
for i in "${!LAYERS[@]}"; do
    LAYER="${LAYERS[$i]}"
    PORT="${PORTS[$i]}"
    
    printf "%-8s" "$LAYER"
    
    for NODE_IP in "${NODES[@]}"; do
        STATE=$(curl -s --connect-timeout 2 http://$NODE_IP:$PORT/node/info 2>/dev/null | jq -r '.state // "DOWN"' 2>/dev/null || echo "DOWN")
        
        case $STATE in
            Ready) printf "%-18s" "✅ Ready" ;;
            Observing) printf "%-18s" "🔄 Observing" ;;
            DOWN) printf "%-18s" "❌ Down" ;;
            *) printf "%-18s" "⚠️  $STATE" ;;
        esac
    done
    echo ""
done

echo ""
echo "=== Cluster Sizes ==="
for i in "${!LAYERS[@]}"; do
    LAYER="${LAYERS[$i]}"
    PORT="${PORTS[$i]}"
    SIZE=$(curl -s --connect-timeout 2 http://$NODE1_IP:$PORT/cluster/info 2>/dev/null | jq 'length' 2>/dev/null || echo "?")
    echo "  $LAYER: $SIZE nodes"
done

echo ""
echo "=== Containers per Node ==="
for NODE_IP in "${NODES[@]}"; do
    echo "  $NODE_IP:"
    ssh_node "$NODE_IP" "docker ps --format '    {{.Names}}: {{.Status}}' 2>/dev/null | grep -E 'gl0|gl1|ml0|cl1|dl1' | sort" 2>/dev/null || echo "    (unreachable)"
done

# Load saved state if available
if [ -f "$SCRIPT_DIR/../../.cluster-state" ]; then
    echo ""
    echo "=== Saved Peer IDs ==="
    cat "$SCRIPT_DIR/../../.cluster-state"
fi
