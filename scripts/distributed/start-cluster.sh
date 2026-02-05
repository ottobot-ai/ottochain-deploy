#!/bin/bash
# Start the full OttoChain distributed cluster
# Usage: ./scripts/distributed/start-cluster.sh [--genesis]
#
# Startup order: GL0 → GL1 → ML0 → CL1 → DL1
# Each layer: Node1 (genesis/initial) → Node2,3 (validators join)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../inventory.sh"

GENESIS_MODE=false
if [ "$1" == "--genesis" ]; then
    GENESIS_MODE=true
    echo "⚠️  GENESIS MODE: Starting fresh cluster"
fi

echo "============================================"
echo "     OttoChain Distributed Cluster Start"
echo "============================================"
echo ""
echo "Nodes:"
echo "  Node 1 (genesis): $NODE1_IP"
echo "  Node 2: $NODE2_IP"
echo "  Node 3: $NODE3_IP"
echo ""

# Helper to start a layer on a node
start_layer() {
    local NODE_IP=$1
    local LAYER=$2      # gl0, gl1, ml0, cl1, dl1
    local MODE=$3       # genesis, initial, validator
    local JAR=$4
    local PUBLIC_PORT=$5
    local P2P_PORT=$6
    local CLI_PORT=$7
    
    local CONTAINER="${LAYER}"
    
    echo "Starting $LAYER on $NODE_IP ($MODE)..."
    
    # Build docker run command
    local EXTRA_ENV=""
    
    # Add peer references for validators
    if [ "$MODE" == "validator" ]; then
        case $LAYER in
            gl0)
                EXTRA_ENV="$EXTRA_ENV -e CL_GLOBAL_L0_PEER_HTTP_HOST=$NODE1_IP"
                EXTRA_ENV="$EXTRA_ENV -e CL_GLOBAL_L0_PEER_HTTP_PORT=$GL0_PUBLIC"
                EXTRA_ENV="$EXTRA_ENV -e CL_GLOBAL_L0_PEER_ID=$GL0_PEER_ID"
                ;;
            gl1)
                EXTRA_ENV="$EXTRA_ENV -e CL_GLOBAL_L0_PEER_HTTP_HOST=$NODE1_IP"
                EXTRA_ENV="$EXTRA_ENV -e CL_GLOBAL_L0_PEER_HTTP_PORT=$GL0_PUBLIC"
                EXTRA_ENV="$EXTRA_ENV -e CL_GLOBAL_L0_PEER_ID=$GL0_PEER_ID"
                EXTRA_ENV="$EXTRA_ENV -e CL_L0_PEER_HTTP_HOST=$NODE1_IP"
                EXTRA_ENV="$EXTRA_ENV -e CL_L0_PEER_HTTP_PORT=$GL1_PUBLIC"
                EXTRA_ENV="$EXTRA_ENV -e CL_L0_PEER_ID=$GL1_PEER_ID"
                ;;
            ml0)
                EXTRA_ENV="$EXTRA_ENV -e CL_GLOBAL_L0_PEER_HTTP_HOST=$NODE1_IP"
                EXTRA_ENV="$EXTRA_ENV -e CL_GLOBAL_L0_PEER_HTTP_PORT=$GL0_PUBLIC"
                EXTRA_ENV="$EXTRA_ENV -e CL_GLOBAL_L0_PEER_ID=$GL0_PEER_ID"
                EXTRA_ENV="$EXTRA_ENV -e CL_L0_PEER_HTTP_HOST=$NODE1_IP"
                EXTRA_ENV="$EXTRA_ENV -e CL_L0_PEER_HTTP_PORT=$ML0_PUBLIC"
                EXTRA_ENV="$EXTRA_ENV -e CL_L0_PEER_ID=$ML0_PEER_ID"
                EXTRA_ENV="$EXTRA_ENV -e CL_L0_TOKEN_IDENTIFIER=$TOKEN_ID"
                ;;
            cl1|dl1)
                EXTRA_ENV="$EXTRA_ENV -e CL_GLOBAL_L0_PEER_HTTP_HOST=$NODE1_IP"
                EXTRA_ENV="$EXTRA_ENV -e CL_GLOBAL_L0_PEER_HTTP_PORT=$GL0_PUBLIC"
                EXTRA_ENV="$EXTRA_ENV -e CL_GLOBAL_L0_PEER_ID=$GL0_PEER_ID"
                EXTRA_ENV="$EXTRA_ENV -e CL_L0_PEER_HTTP_HOST=$NODE1_IP"
                EXTRA_ENV="$EXTRA_ENV -e CL_L0_PEER_HTTP_PORT=$ML0_PUBLIC"
                EXTRA_ENV="$EXTRA_ENV -e CL_L0_PEER_ID=$ML0_PEER_ID"
                EXTRA_ENV="$EXTRA_ENV -e CL_L0_TOKEN_IDENTIFIER=$TOKEN_ID"
                ;;
        esac
    fi
    
    # For metagraph layers, always need token ID
    if [[ "$LAYER" =~ ^(ml0|cl1|dl1)$ ]] && [ -n "$TOKEN_ID" ]; then
        EXTRA_ENV="$EXTRA_ENV -e CL_L0_TOKEN_IDENTIFIER=$TOKEN_ID"
    fi
    
    # Determine run command
    local RUN_CMD="run-validator"
    local EXTRA_MOUNTS=""
    case $MODE in
        genesis)
            if [ "$LAYER" == "gl0" ]; then
                RUN_CMD="run-genesis /genesis/genesis.csv"
                EXTRA_MOUNTS="-v $REMOTE_DIR/genesis:/genesis:ro"
            elif [ "$LAYER" == "ml0" ]; then
                RUN_CMD="run-genesis $REMOTE_DATA/genesis.snapshot"
                EXTRA_MOUNTS="-v $REMOTE_DATA:/data"
            fi
            ;;
        initial)
            RUN_CMD="run-initial-validator"
            ;;
    esac
    
    ssh_node "$NODE_IP" "source $REMOTE_DIR/.env.local && docker rm -f $CONTAINER 2>/dev/null || true && docker run -d --name $CONTAINER \
        --network $NETWORK \
        -p $PUBLIC_PORT:$PUBLIC_PORT -p $P2P_PORT:$P2P_PORT -p $CLI_PORT:$CLI_PORT \
        -v $REMOTE_JARS:/jars:ro \
        -v $REMOTE_KEYS:/keys:ro \
        $EXTRA_MOUNTS \
        -e CL_KEYSTORE=/keys/key.p12 \
        -e CL_KEYALIAS=\$CL_KEYALIAS \
        -e CL_PASSWORD=\$CL_PASSWORD \
        -e CL_PUBLIC_HTTP_PORT=$PUBLIC_PORT \
        -e CL_P2P_HTTP_PORT=$P2P_PORT \
        -e CL_CLI_HTTP_PORT=$CLI_PORT \
        -e CL_EXTERNAL_IP=$NODE_IP \
        -e CL_APP_ENV=dev \
        -e CL_COLLATERAL=0 \
        $EXTRA_ENV \
        $JAVA_IMAGE java -jar /jars/$JAR $RUN_CMD"
}

# Helper to get peer ID from a running node
get_peer_id() {
    local NODE_IP=$1
    local PORT=$2
    curl -s --connect-timeout 5 http://$NODE_IP:$PORT/node/info | jq -r '.id // empty'
}

# Helper to join a validator to cluster
join_cluster() {
    local NODE_IP=$1
    local CLI_PORT=$2
    local GENESIS_IP=$3
    local GENESIS_P2P=$4
    local PEER_ID=$5
    
    echo "  Joining $NODE_IP to cluster..."
    ssh_node "$NODE_IP" "docker exec ${LAYER} curl -s -X POST 'http://127.0.0.1:$CLI_PORT/cluster/join' \
        -H 'Content-Type: application/json' \
        -d '{\"id\": \"$PEER_ID\", \"ip\": \"$GENESIS_IP\", \"p2pPort\": $GENESIS_P2P}'" || true
}

wait_for_ready() {
    local NODE_IP=$1
    local PORT=$2
    local MAX_WAIT=${3:-60}
    
    echo -n "  Waiting for $NODE_IP:$PORT to be ready..."
    for i in $(seq 1 $MAX_WAIT); do
        STATE=$(curl -s --connect-timeout 2 http://$NODE_IP:$PORT/node/info | jq -r '.state // empty' 2>/dev/null)
        if [ "$STATE" == "Ready" ]; then
            echo " Ready!"
            return 0
        fi
        echo -n "."
        sleep 1
    done
    echo " TIMEOUT (state: $STATE)"
    return 1
}

# ============================================
# GL0 Layer
# ============================================
echo ""
echo "=== Starting GL0 Layer ==="

if [ "$GENESIS_MODE" = true ]; then
    # Create genesis.csv on Node 1
    ADDR=$(ssh_node "$NODE1_IP" "source $REMOTE_DIR/.env.local && docker run --rm \
        -e CL_KEYSTORE=/keys/key.p12 -e CL_KEYALIAS=\$CL_KEYALIAS -e CL_PASSWORD=\$CL_PASSWORD \
        -v $REMOTE_KEYS:/keys -v $REMOTE_JARS:/jars \
        $JAVA_IMAGE java -jar /jars/cl-wallet.jar show-address 2>/dev/null | grep -oP 'DAG[a-zA-Z0-9]+'")
    ssh_node "$NODE1_IP" "echo '$ADDR,1000000000000000' > $REMOTE_DIR/genesis/genesis.csv"
    echo "Genesis allocation: $ADDR"
fi

# Start GL0 on Node 1
start_layer "$NODE1_IP" "gl0" "genesis" "dag-l0.jar" $GL0_PUBLIC $GL0_P2P $GL0_CLI
wait_for_ready "$NODE1_IP" $GL0_PUBLIC 60

# Get GL0 peer ID
GL0_PEER_ID=$(get_peer_id "$NODE1_IP" $GL0_PUBLIC)
echo "GL0 Peer ID: ${GL0_PEER_ID:0:20}..."

# Start GL0 validators
for NODE_IP in "$NODE2_IP" "$NODE3_IP"; do
    start_layer "$NODE_IP" "gl0" "validator" "dag-l0.jar" $GL0_PUBLIC $GL0_P2P $GL0_CLI
done
sleep 15

# Join GL0 validators
LAYER="gl0"
for NODE_IP in "$NODE2_IP" "$NODE3_IP"; do
    join_cluster "$NODE_IP" $GL0_CLI "$NODE1_IP" $GL0_P2P "$GL0_PEER_ID"
done
sleep 5

echo "GL0 cluster size: $(curl -s http://$NODE1_IP:$GL0_PUBLIC/cluster/info | jq 'length')"

# ============================================
# GL1 Layer
# ============================================
echo ""
echo "=== Starting GL1 Layer ==="

start_layer "$NODE1_IP" "gl1" "initial" "dag-l1.jar" $GL1_PUBLIC $GL1_P2P $GL1_CLI
wait_for_ready "$NODE1_IP" $GL1_PUBLIC 60

GL1_PEER_ID=$(get_peer_id "$NODE1_IP" $GL1_PUBLIC)
echo "GL1 Peer ID: ${GL1_PEER_ID:0:20}..."

for NODE_IP in "$NODE2_IP" "$NODE3_IP"; do
    start_layer "$NODE_IP" "gl1" "validator" "dag-l1.jar" $GL1_PUBLIC $GL1_P2P $GL1_CLI
done
sleep 15

LAYER="gl1"
for NODE_IP in "$NODE2_IP" "$NODE3_IP"; do
    join_cluster "$NODE_IP" $GL1_CLI "$NODE1_IP" $GL1_P2P "$GL1_PEER_ID"
done
sleep 5

echo "GL1 cluster size: $(curl -s http://$NODE1_IP:$GL1_PUBLIC/cluster/info | jq 'length')"

# ============================================
# ML0 Layer
# ============================================
echo ""
echo "=== Starting ML0 Layer ==="

if [ "$GENESIS_MODE" = true ]; then
    # Create metagraph genesis snapshot
    echo "Creating metagraph genesis snapshot..."
    ssh_node "$NODE1_IP" "source $REMOTE_DIR/.env.local && docker run --rm \
        -e CL_KEYSTORE=/keys/key.p12 -e CL_KEYALIAS=\$CL_KEYALIAS -e CL_PASSWORD=\$CL_PASSWORD \
        -v $REMOTE_KEYS:/keys -v $REMOTE_JARS:/jars -v $REMOTE_DATA:/data -v $REMOTE_DIR/genesis:/genesis:ro \
        -w /data \
        $JAVA_IMAGE java -jar /jars/metagraph-l0.jar create-genesis /genesis/genesis.csv"
fi

start_layer "$NODE1_IP" "ml0" "genesis" "metagraph-l0.jar" $ML0_PUBLIC $ML0_P2P $ML0_CLI
wait_for_ready "$NODE1_IP" $ML0_PUBLIC 60

ML0_PEER_ID=$(get_peer_id "$NODE1_IP" $ML0_PUBLIC)
echo "ML0 Peer ID: ${ML0_PEER_ID:0:20}..."

# Get token ID
TOKEN_ID=$(curl -s http://$NODE1_IP:$GL0_PUBLIC/global-snapshots/latest | jq -r '.value.stateChannelSnapshots | keys[0] // empty')
echo "Token ID: ${TOKEN_ID:0:20}..."

for NODE_IP in "$NODE2_IP" "$NODE3_IP"; do
    start_layer "$NODE_IP" "ml0" "validator" "metagraph-l0.jar" $ML0_PUBLIC $ML0_P2P $ML0_CLI
done
sleep 20

LAYER="ml0"
for NODE_IP in "$NODE2_IP" "$NODE3_IP"; do
    join_cluster "$NODE_IP" $ML0_CLI "$NODE1_IP" $ML0_P2P "$ML0_PEER_ID"
done
sleep 5

echo "ML0 cluster size: $(curl -s http://$NODE1_IP:$ML0_PUBLIC/cluster/info | jq 'length')"

# ============================================
# CL1 Layer
# ============================================
echo ""
echo "=== Starting CL1 Layer ==="

start_layer "$NODE1_IP" "cl1" "initial" "currency-l1.jar" $CL1_PUBLIC $CL1_P2P $CL1_CLI
wait_for_ready "$NODE1_IP" $CL1_PUBLIC 60

CL1_PEER_ID=$(get_peer_id "$NODE1_IP" $CL1_PUBLIC)
echo "CL1 Peer ID: ${CL1_PEER_ID:0:20}..."

for NODE_IP in "$NODE2_IP" "$NODE3_IP"; do
    start_layer "$NODE_IP" "cl1" "validator" "currency-l1.jar" $CL1_PUBLIC $CL1_P2P $CL1_CLI
done
sleep 15

LAYER="cl1"
for NODE_IP in "$NODE2_IP" "$NODE3_IP"; do
    join_cluster "$NODE_IP" $CL1_CLI "$NODE1_IP" $CL1_P2P "$CL1_PEER_ID"
done
sleep 5

echo "CL1 cluster size: $(curl -s http://$NODE1_IP:$CL1_PUBLIC/cluster/info | jq 'length')"

# ============================================
# DL1 Layer
# ============================================
echo ""
echo "=== Starting DL1 Layer ==="

start_layer "$NODE1_IP" "dl1" "initial" "data-l1.jar" $DL1_PUBLIC $DL1_P2P $DL1_CLI
wait_for_ready "$NODE1_IP" $DL1_PUBLIC 60

DL1_PEER_ID=$(get_peer_id "$NODE1_IP" $DL1_PUBLIC)
echo "DL1 Peer ID: ${DL1_PEER_ID:0:20}..."

for NODE_IP in "$NODE2_IP" "$NODE3_IP"; do
    start_layer "$NODE_IP" "dl1" "validator" "data-l1.jar" $DL1_PUBLIC $DL1_P2P $DL1_CLI
done
sleep 15

LAYER="dl1"
for NODE_IP in "$NODE2_IP" "$NODE3_IP"; do
    join_cluster "$NODE_IP" $DL1_CLI "$NODE1_IP" $DL1_P2P "$DL1_PEER_ID"
done
sleep 5

echo "DL1 cluster size: $(curl -s http://$NODE1_IP:$DL1_PUBLIC/cluster/info | jq 'length')"

# ============================================
# Summary
# ============================================
echo ""
echo "============================================"
echo "     Cluster Startup Complete"
echo "============================================"
echo ""
echo "Peer IDs:"
echo "  GL0: $GL0_PEER_ID"
echo "  GL1: $GL1_PEER_ID"
echo "  ML0: $ML0_PEER_ID"
echo "  CL1: $CL1_PEER_ID"
echo "  DL1: $DL1_PEER_ID"
echo ""
echo "Token ID: $TOKEN_ID"
echo ""

# Save peer IDs for later use
cat > "$SCRIPT_DIR/../../.cluster-state" << EOF
GL0_PEER_ID=$GL0_PEER_ID
GL1_PEER_ID=$GL1_PEER_ID
ML0_PEER_ID=$ML0_PEER_ID
CL1_PEER_ID=$CL1_PEER_ID
DL1_PEER_ID=$DL1_PEER_ID
TOKEN_ID=$TOKEN_ID
EOF

echo "Run ./scripts/distributed/status-cluster.sh to check health"
