#!/bin/bash
# Setup all OttoChain nodes from scratch
# Usage: ./scripts/distributed/setup-all-nodes.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../inventory.sh"

echo "============================================"
echo "     OttoChain Distributed Node Setup"
echo "============================================"
echo ""
echo "Nodes: ${NODES[*]}"
echo ""

# Check for local secrets
if [ ! -f "$SCRIPT_DIR/../../secrets/.env.cluster" ]; then
    echo "Creating secrets file..."
    mkdir -p "$SCRIPT_DIR/../../secrets"
    CLUSTER_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
    cat > "$SCRIPT_DIR/../../secrets/.env.cluster" << EOF
# OttoChain cluster secrets
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
CL_PASSWORD=$CLUSTER_PASSWORD
CL_KEYALIAS=alias
EOF
    echo "Generated new cluster password in secrets/.env.cluster"
fi

source "$SCRIPT_DIR/../../secrets/.env.cluster"

# Setup each node
for i in "${!NODES[@]}"; do
    NODE_IP="${NODES[$i]}"
    NODE_NUM=$((i + 1))
    
    echo ""
    echo "============================================"
    echo "Setting up Node $NODE_NUM: $NODE_IP"
    echo "============================================"
    
    # Check connectivity
    if ! ssh_node "$NODE_IP" "echo 'Connected'" 2>/dev/null; then
        echo "ERROR: Cannot connect to $NODE_IP"
        continue
    fi
    
    # Install prerequisites
    echo "Installing prerequisites..."
    ssh_node "$NODE_IP" << 'REMOTE_PREREQ'
set -e

# Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    apt-get update
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# jq
if ! command -v jq &> /dev/null; then
    apt-get install -y jq
fi

echo "Prerequisites installed"
REMOTE_PREREQ
    
    # Create directories
    echo "Creating directories..."
    ssh_node "$NODE_IP" "mkdir -p $REMOTE_DIR/{jars,keys,data,scripts,genesis} && chmod 700 $REMOTE_KEYS"
    
    # Create .env.local with secrets
    echo "Setting up secrets..."
    ssh_node "$NODE_IP" "cat > $REMOTE_DIR/.env.local << EOF
# Node $NODE_NUM secrets
HOST_IP=$NODE_IP
CL_PASSWORD=$CL_PASSWORD
CL_KEYALIAS=$CL_KEYALIAS
EOF
chmod 600 $REMOTE_DIR/.env.local"
    
    # Generate key if not exists
    echo "Checking keys..."
    if ssh_node "$NODE_IP" "[ ! -f $REMOTE_KEYS/key.p12 ]"; then
        echo "Generating keypair..."
        # We'll do this after JAR deployment
    else
        echo "Key already exists"
    fi
    
    # Create Docker network
    ssh_node "$NODE_IP" "docker network create $NETWORK 2>/dev/null || true"
    
    echo "✓ Node $NODE_NUM setup complete"
done

echo ""
echo "============================================"
echo "     All Nodes Setup Complete"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Deploy JARs: ./scripts/distributed/deploy-jars.sh"
echo "  2. Generate keys: ./scripts/distributed/generate-keys.sh"
echo "  3. Start cluster: ./scripts/distributed/start-cluster.sh"
