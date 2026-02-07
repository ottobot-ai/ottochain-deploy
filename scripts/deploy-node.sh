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
    1) NODE_IP="${NODE1_IP:-${NODE1_IP}}" ;;
    2) NODE_IP="${NODE2_IP:-${NODE2_IP}}" ;;
    3) NODE_IP="${NODE3_IP:-${NODE3_IP}}" ;;
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
REPO_ROOT="$SCRIPT_DIR/.."
scp $SSH_OPTS "$REPO_ROOT/docker/metagraph/docker-compose.yml" root@$NODE_IP:$REMOTE_DIR/
scp $SSH_OPTS "$REPO_ROOT/docker/metagraph/nodes/node${NODE_NUM}.env" root@$NODE_IP:$REMOTE_DIR/.env

# Copy keystore if not exists
if [[ -f "$REPO_ROOT/keys/node${NODE_NUM}.p12" ]]; then
    scp $SSH_OPTS "$REPO_ROOT/keys/node${NODE_NUM}.p12" root@$NODE_IP:$REMOTE_DIR/keys/key.p12
fi

# Copy genesis.csv if exists
if [[ -f "$REPO_ROOT/genesis.csv" ]]; then
    scp $SSH_OPTS "$REPO_ROOT/genesis.csv" root@$NODE_IP:$REMOTE_DIR/genesis/
fi

# If genesis mode, wipe data
if [[ "$GENESIS_MODE" == "true" ]]; then
    echo "Wiping previous state (genesis mode)..."
    ssh $SSH_OPTS root@$NODE_IP "cd $REMOTE_DIR && rm -rf data/* logs/*"
fi

# Copy JARs if they exist locally
JARS_DIR="${JARS_DIR:-$REPO_ROOT/docker/jars}"
if [[ -d "$JARS_DIR" ]] && ls "$JARS_DIR"/*.jar 1>/dev/null 2>&1; then
    echo "Copying JARs..."
    scp $SSH_OPTS "$JARS_DIR"/*.jar root@$NODE_IP:$REMOTE_DIR/jars/
fi

# Pull base image
echo "Pulling base Docker image..."
ssh $SSH_OPTS root@$NODE_IP "docker pull eclipse-temurin:21-jdk"

echo "✓ Node $NODE_NUM deployed"
