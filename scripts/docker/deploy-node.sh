#!/bin/bash
# Deploy OttoChain Docker stack to a single node
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../inventory.sh" 2>/dev/null || true

usage() {
    echo "Usage: $0 <node_number> [--genesis]"
    echo ""
    echo "  node_number: 1, 2, or 3"
    echo "  --genesis: Wipe state and start fresh (default: preserve state)"
    exit 1
}

NODE_NUM="$1"
GENESIS_MODE=""

if [[ -z "$NODE_NUM" ]]; then
    usage
fi

shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --genesis) GENESIS_MODE="true"; shift ;;
        *) usage ;;
    esac
done

# Get node IP from inventory
case "$NODE_NUM" in
    1) NODE_IP="${NODE1_IP:-5.78.90.207}" ;;
    2) NODE_IP="${NODE2_IP:-5.78.113.25}" ;;
    3) NODE_IP="${NODE3_IP:-5.78.107.77}" ;;
    *) echo "Invalid node number: $NODE_NUM"; exit 1 ;;
esac

SSH_KEY="${SSH_KEY:-$HOME/.ssh/hetzner_ottobot}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $SSH_KEY"
REMOTE_DIR="/opt/ottochain"

echo "=== Deploying to Node $NODE_NUM ($NODE_IP) ==="

# Create remote directory structure
ssh $SSH_OPTS root@$NODE_IP "mkdir -p $REMOTE_DIR/{data,logs,jars}"

# Copy docker-compose and env file
echo "Copying Docker configuration..."
scp $SSH_OPTS "$SCRIPT_DIR/../../docker/docker-compose.yml" root@$NODE_IP:$REMOTE_DIR/
scp $SSH_OPTS "$SCRIPT_DIR/../../docker/nodes/node${NODE_NUM}.env" root@$NODE_IP:$REMOTE_DIR/.env

# Copy keystore if not exists
if [[ -f "$SCRIPT_DIR/../../keys/node${NODE_NUM}.p12" ]]; then
    scp $SSH_OPTS "$SCRIPT_DIR/../../keys/node${NODE_NUM}.p12" root@$NODE_IP:$REMOTE_DIR/key.p12
fi

# Copy genesis.csv if exists
if [[ -f "$SCRIPT_DIR/../../genesis.csv" ]]; then
    scp $SSH_OPTS "$SCRIPT_DIR/../../genesis.csv" root@$NODE_IP:$REMOTE_DIR/
fi

# If genesis mode, wipe data
if [[ "$GENESIS_MODE" == "true" ]]; then
    echo "Wiping previous state (genesis mode)..."
    ssh $SSH_OPTS root@$NODE_IP "cd $REMOTE_DIR && rm -rf data/* logs/*"
fi

# Export metagraph image (or pull from registry)
if [[ -n "$DOCKER_REGISTRY" ]]; then
    echo "Pulling image from registry..."
    ssh $SSH_OPTS root@$NODE_IP "docker pull $DOCKER_REGISTRY/ottochain:${VERSION:-latest}"
else
    echo "Exporting and transferring Docker image..."
    docker save ottochain:${VERSION:-latest} | ssh $SSH_OPTS root@$NODE_IP "docker load"
fi

echo "✓ Node $NODE_NUM deployed"
