#!/bin/bash
# Deploy OttoChain to Hetzner nodes
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"

# Node configuration
declare -A NODES=(
  ["node1"]="hetzner-node1"
  ["node2"]="hetzner-node2"
  ["node3"]="hetzner-node3"
)

declare -A NODE_IPS=(
  ["node1"]="5.78.90.207"
  ["node2"]="5.78.113.25"
  ["node3"]="5.78.107.77"
)

REMOTE_DIR="/opt/ottochain-docker"

echo "=== OttoChain Deployment ==="

# Check JARs exist
if [ ! -f "$DEPLOY_DIR/docker/jars/dag-l0.jar" ]; then
  echo "ERROR: JARs not built. Run ./scripts/build-jars.sh first"
  exit 1
fi

for node in "${!NODES[@]}"; do
  host="${NODES[$node]}"
  ip="${NODE_IPS[$node]}"
  
  echo ""
  echo "=== Deploying to $node ($host / $ip) ==="
  
  # Create remote directory
  ssh "$host" "mkdir -p $REMOTE_DIR/{keys,data,genesis,jars}"
  
  # Copy Docker files
  echo "Copying Docker files..."
  scp "$DEPLOY_DIR/docker/Dockerfile" "$host:$REMOTE_DIR/"
  scp "$DEPLOY_DIR/docker/entrypoint.sh" "$host:$REMOTE_DIR/"
  scp "$DEPLOY_DIR/docker/docker-compose.node.yml" "$host:$REMOTE_DIR/docker-compose.yml"
  
  # Copy JARs
  echo "Copying JARs (this may take a while)..."
  rsync -avz --progress "$DEPLOY_DIR/docker/jars/" "$host:$REMOTE_DIR/jars/"
  
  # Generate node-specific .env if not exists
  if ! ssh "$host" "[ -f $REMOTE_DIR/.env ]"; then
    echo "Generating .env for $node..."
    cat << EOF | ssh "$host" "cat > $REMOTE_DIR/.env"
# $node configuration
NODE_ALIAS=$node
NODE_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
EXTERNAL_IP=$ip

# Genesis node is node1
GL0_MODE=validator
ML0_MODE=validator
CL1_MODE=validator
DL1_MODE=validator

# Peer configuration (set after genesis)
GL0_PEER_HOST=
GL0_PEER_PORT=9000
GL0_PEER_ID=

ML0_PEER_HOST=
ML0_PEER_PORT=9200
ML0_PEER_ID=

CL1_PEER_HOST=
CL1_PEER_PORT=9300
CL1_PEER_ID=

DL1_PEER_HOST=
DL1_PEER_PORT=9400
DL1_PEER_ID=

# Node IDs (populated after key generation)
GL0_NODE_ID=
ML0_NODE_ID=
EOF
  fi
  
  # Generate keys if not exist
  if ! ssh "$host" "[ -f $REMOTE_DIR/keys/node.p12 ]"; then
    echo "Generating keys for $node..."
    # New keytool uses env vars: CL_KEYSTORE, CL_KEYALIAS, CL_PASSWORD
    ssh "$host" "cd $REMOTE_DIR && source .env && docker run --rm \
      -e CL_KEYSTORE=/keys/node.p12 \
      -e CL_KEYALIAS=\$NODE_ALIAS \
      -e CL_PASSWORD=\$NODE_PASSWORD \
      -v \$(pwd)/keys:/keys \
      -v \$(pwd)/jars:/jars \
      eclipse-temurin:21-jre-jammy java -jar /jars/keytool.jar generate"
    
    # Extract node ID using wallet.jar show-id
    NODE_ID=$(ssh "$host" "cd $REMOTE_DIR && source .env && docker run --rm \
      -e CL_KEYSTORE=/keys/node.p12 \
      -e CL_KEYALIAS=\$NODE_ALIAS \
      -e CL_PASSWORD=\$NODE_PASSWORD \
      -v \$(pwd)/keys:/keys \
      -v \$(pwd)/jars:/jars \
      eclipse-temurin:21-jre-jammy java -jar /jars/wallet.jar show-id 2>/dev/null | grep -oP 'DAG[a-zA-Z0-9]+'")
    echo "Node ID: $NODE_ID"
    
    # Update .env with node ID
    ssh "$host" "cd $REMOTE_DIR && sed -i 's/GL0_NODE_ID=.*/GL0_NODE_ID=$NODE_ID/' .env"
    ssh "$host" "cd $REMOTE_DIR && sed -i 's/ML0_NODE_ID=.*/ML0_NODE_ID=$NODE_ID/' .env"
  fi
  
  # Build Docker image on node
  echo "Building Docker image on $node..."
  ssh "$host" "cd $REMOTE_DIR && docker build -t ottochain/node:latest ."
  
  echo "✅ $node deployed"
done

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Next steps:"
echo "1. Run genesis on node1: ./scripts/start-genesis.sh"
echo "2. Update peer configs and join other nodes"
