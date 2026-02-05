#!/bin/bash
# Deploy JARs to all OttoChain nodes
# Usage: ./scripts/distributed/deploy-jars.sh [--from-node1]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../inventory.sh"

JARS_SOURCE="${JARS_SOURCE:-$SCRIPT_DIR/../../docker/jars}"
FROM_NODE1=false

if [ "$1" == "--from-node1" ]; then
    FROM_NODE1=true
    JARS_SOURCE="root@$NODE1_IP:$REMOTE_JARS"
fi

echo "============================================"
echo "     Deploy JARs to All Nodes"
echo "============================================"
echo ""
echo "Source: $JARS_SOURCE"
echo "Nodes: ${NODES[*]}"
echo ""

REQUIRED_JARS=(
    "dag-l0.jar"
    "dag-l1.jar"
    "metagraph-l0.jar"
    "currency-l1.jar"
    "data-l1.jar"
    "cl-keytool.jar"
    "cl-wallet.jar"
)

# Verify source JARs exist
if [ "$FROM_NODE1" = false ]; then
    echo "Checking local JARs..."
    for jar in "${REQUIRED_JARS[@]}"; do
        if [ ! -f "$JARS_SOURCE/$jar" ]; then
            echo "ERROR: Missing $jar in $JARS_SOURCE"
            echo "Build JARs first or use --from-node1 to copy from Node 1"
            exit 1
        fi
    done
    echo "All required JARs found"
fi

# Deploy to each node
for i in "${!NODES[@]}"; do
    NODE_IP="${NODES[$i]}"
    NODE_NUM=$((i + 1))
    
    echo ""
    echo "=== Deploying to Node $NODE_NUM ($NODE_IP) ==="
    
    if [ "$FROM_NODE1" = true ] && [ "$NODE_IP" = "$NODE1_IP" ]; then
        echo "Skipping Node 1 (source)"
        continue
    fi
    
    # Create jars directory
    ssh_node "$NODE_IP" "mkdir -p $REMOTE_JARS"
    
    if [ "$FROM_NODE1" = true ]; then
        # Copy from Node 1 to this node via local relay
        echo "Copying from Node 1..."
        for jar in "${REQUIRED_JARS[@]}"; do
            echo "  $jar..."
            ssh_node "$NODE1_IP" "cat $REMOTE_JARS/$jar" | ssh_node "$NODE_IP" "cat > $REMOTE_JARS/$jar"
        done
    else
        # Copy from local
        echo "Uploading JARs (this may take a while)..."
        for jar in "${REQUIRED_JARS[@]}"; do
            echo "  $jar..."
            scp_to_node "$NODE_IP" "$JARS_SOURCE/$jar" "$REMOTE_JARS/$jar"
        done
    fi
    
    # Verify
    echo "Verifying..."
    ssh_node "$NODE_IP" "ls -la $REMOTE_JARS/*.jar | wc -l"
    
    echo "✓ Node $NODE_NUM complete"
done

echo ""
echo "============================================"
echo "     JAR Deployment Complete"
echo "============================================"
