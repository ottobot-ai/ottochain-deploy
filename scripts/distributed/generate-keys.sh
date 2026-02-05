#!/bin/bash
# Generate keys on all OttoChain nodes
# Usage: ./scripts/distributed/generate-keys.sh [--force]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../inventory.sh"

FORCE=false
if [ "$1" == "--force" ]; then
    FORCE=true
fi

echo "============================================"
echo "     Generate Keys on All Nodes"
echo "============================================"
echo ""

for i in "${!NODES[@]}"; do
    NODE_IP="${NODES[$i]}"
    NODE_NUM=$((i + 1))
    
    echo "=== Node $NODE_NUM ($NODE_IP) ==="
    
    # Check if key exists
    if ssh_node "$NODE_IP" "[ -f $REMOTE_KEYS/key.p12 ]" && [ "$FORCE" = false ]; then
        echo "Key already exists (use --force to regenerate)"
        # Show wallet address
        ADDR=$(ssh_node "$NODE_IP" "source $REMOTE_DIR/.env.local && docker run --rm \
            -e CL_KEYSTORE=/keys/key.p12 \
            -e CL_KEYALIAS=\$CL_KEYALIAS \
            -e CL_PASSWORD=\$CL_PASSWORD \
            -v $REMOTE_KEYS:/keys \
            -v $REMOTE_JARS:/jars \
            $JAVA_IMAGE java -jar /jars/cl-wallet.jar show-address 2>/dev/null | grep -oP 'DAG[a-zA-Z0-9]+'" || echo "unknown")
        echo "  Address: $ADDR"
        continue
    fi
    
    echo "Generating new keypair..."
    ssh_node "$NODE_IP" "source $REMOTE_DIR/.env.local && docker run --rm \
        -e CL_KEYSTORE=/keys/key.p12 \
        -e CL_KEYALIAS=\$CL_KEYALIAS \
        -e CL_PASSWORD=\$CL_PASSWORD \
        -v $REMOTE_KEYS:/keys \
        -v $REMOTE_JARS:/jars \
        $JAVA_IMAGE java -jar /jars/cl-keytool.jar generate"
    
    # Show wallet address
    ADDR=$(ssh_node "$NODE_IP" "source $REMOTE_DIR/.env.local && docker run --rm \
        -e CL_KEYSTORE=/keys/key.p12 \
        -e CL_KEYALIAS=\$CL_KEYALIAS \
        -e CL_PASSWORD=\$CL_PASSWORD \
        -v $REMOTE_KEYS:/keys \
        -v $REMOTE_JARS:/jars \
        $JAVA_IMAGE java -jar /jars/cl-wallet.jar show-address 2>/dev/null | grep -oP 'DAG[a-zA-Z0-9]+'" || echo "unknown")
    
    echo "  ✓ Generated key for Node $NODE_NUM"
    echo "  Address: $ADDR"
done

echo ""
echo "============================================"
echo "     Key Generation Complete"
echo "============================================"
