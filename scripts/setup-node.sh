#!/bin/bash
# Setup a fresh OttoChain metagraph node from scratch
# Usage: ./scripts/setup-node.sh <host-ip> [ssh-key-path]
#
# Prerequisites:
# - JARs built in docker/jars/ (run build-jars.sh first)
# - SSH access to target server
# - Server should be Ubuntu 22.04+ with root access

set -e

HOST_IP=${1:?Usage: setup-node.sh <host-ip> [ssh-key-path]}
SSH_KEY=${2:-~/.ssh/hetzner_ottobot}
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=accept-new"
SSH_CMD="ssh $SSH_OPTS root@$HOST_IP"
SCP_CMD="scp $SSH_OPTS"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
REMOTE_DIR="/opt/ottochain"

echo "============================================"
echo "     OttoChain Node Setup"
echo "============================================"
echo "Target: root@$HOST_IP"
echo "Remote: $REMOTE_DIR"
echo ""

# Check for JARs
if [ ! -f "$DEPLOY_DIR/docker/jars/metagraph-l0.jar" ]; then
    echo "ERROR: JARs not found in docker/jars/"
    echo "Build them first: ./scripts/build-jars.sh"
    exit 1
fi

# ============================================
# PHASE 1: Server Prerequisites
# ============================================
echo "=== Phase 1: Server Prerequisites ==="

$SSH_CMD << 'REMOTE_SETUP'
set -e

# Install Docker if not present
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
    echo "Docker installed"
else
    echo "Docker already installed"
fi

# Install jq
if ! command -v jq &> /dev/null; then
    apt-get install -y jq
fi

# Create directories
mkdir -p /opt/ottochain/{jars,keys,keys3,keys4,keys5,keys6,keys7,keys8,data,scripts,genesis}
chmod 700 /opt/ottochain/keys*

echo "Server prerequisites complete"
REMOTE_SETUP

# ============================================
# PHASE 2: Upload Files
# ============================================
echo ""
echo "=== Phase 2: Uploading Files ==="

# Upload JARs
echo "Uploading JARs..."
$SCP_CMD "$DEPLOY_DIR/docker/jars/"*.jar root@$HOST_IP:$REMOTE_DIR/jars/

# Upload scripts
echo "Uploading scripts..."
$SCP_CMD "$SCRIPT_DIR/"*.sh root@$HOST_IP:$REMOTE_DIR/scripts/
$SCP_CMD "$SCRIPT_DIR/.env.example" root@$HOST_IP:$REMOTE_DIR/

# Make scripts executable
$SSH_CMD "chmod +x $REMOTE_DIR/scripts/*.sh"

# ============================================
# PHASE 3: Generate Secrets & Keys
# ============================================
echo ""
echo "=== Phase 3: Secrets & Keys ==="

# Check if .env.local already exists
if $SSH_CMD "[ -f $REMOTE_DIR/.env.local ]"; then
    echo ".env.local already exists, keeping existing secrets"
else
    echo "Generating new secrets..."
    KEYSTORE_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
    
    $SSH_CMD "cat > $REMOTE_DIR/.env.local << EOF
# OttoChain secrets for $HOST_IP
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

HOST_IP=$HOST_IP
CL_PASSWORD=$KEYSTORE_PASSWORD
CL_KEYALIAS=alias
EOF"
    echo "Created .env.local with generated password"
fi

# Generate keys if not present
generate_key() {
    local key_dir=$1
    local key_name=$2
    
    if $SSH_CMD "[ -f $key_dir/key.p12 ]"; then
        echo "Key already exists: $key_dir"
    else
        echo "Generating key: $key_dir"
        $SSH_CMD "source $REMOTE_DIR/.env.local && docker run --rm \
            -e CL_KEYSTORE=/keys/key.p12 \
            -e CL_KEYALIAS=\$CL_KEYALIAS \
            -e CL_PASSWORD=\$CL_PASSWORD \
            -v $key_dir:/keys \
            -v $REMOTE_DIR/jars:/jars \
            eclipse-temurin:21-jre-jammy \
            java -jar /jars/cl-keytool.jar generate"
    fi
}

echo "Generating node keys (9 total for all layers)..."
generate_key "$REMOTE_DIR/keys" "main"
for i in 3 4 5 6 7 8; do
    generate_key "$REMOTE_DIR/keys$i" "key$i"
done

# ============================================
# PHASE 4: Create Genesis
# ============================================
echo ""
echo "=== Phase 4: Genesis Setup ==="

# Get main wallet address for genesis allocation
GENESIS_ADDRESS=$($SSH_CMD "source $REMOTE_DIR/.env.local && docker run --rm \
    -e CL_KEYSTORE=/keys/key.p12 \
    -e CL_KEYALIAS=\$CL_KEYALIAS \
    -e CL_PASSWORD=\$CL_PASSWORD \
    -v $REMOTE_DIR/keys:/keys \
    -v $REMOTE_DIR/jars:/jars \
    eclipse-temurin:21-jre-jammy \
    java -jar /jars/cl-wallet.jar show-address 2>/dev/null | grep -oP 'DAG[a-zA-Z0-9]+'")

echo "Genesis address: $GENESIS_ADDRESS"

# Create genesis.csv if not exists
if ! $SSH_CMD "[ -f $REMOTE_DIR/genesis/genesis.csv ]"; then
    echo "Creating genesis.csv with initial allocation..."
    $SSH_CMD "echo '$GENESIS_ADDRESS,1000000000000000' > $REMOTE_DIR/genesis/genesis.csv"
fi

# Create genesis snapshot if not exists
if ! $SSH_CMD "[ -f $REMOTE_DIR/data/genesis.snapshot ]"; then
    echo "Creating genesis snapshot..."
    $SSH_CMD "source $REMOTE_DIR/.env.local && docker run --rm \
        -e CL_KEYSTORE=/keys/key.p12 \
        -e CL_KEYALIAS=\$CL_KEYALIAS \
        -e CL_PASSWORD=\$CL_PASSWORD \
        -v $REMOTE_DIR/keys:/keys \
        -v $REMOTE_DIR/jars:/jars \
        -v $REMOTE_DIR/genesis:/genesis \
        -v $REMOTE_DIR/data:/data \
        -w /data \
        eclipse-temurin:21-jre-jammy \
        java -jar /jars/metagraph-l0.jar create-genesis /genesis/genesis.csv"
fi

# ============================================
# PHASE 5: Create Docker Network
# ============================================
echo ""
echo "=== Phase 5: Docker Network ==="
$SSH_CMD "docker network create ottochain_ottochain 2>/dev/null || true"

# ============================================
# Summary
# ============================================
echo ""
echo "============================================"
echo "     Setup Complete!"
echo "============================================"
echo ""
echo "Node: $HOST_IP"
echo "Genesis Address: $GENESIS_ADDRESS"
echo ""
echo "Next steps:"
echo "  1. SSH to server: ssh -i $SSH_KEY root@$HOST_IP"
echo "  2. Start the cluster: /opt/ottochain/scripts/start-all.sh"
echo ""
echo "Or from here, run:"
echo "  ssh -i $SSH_KEY root@$HOST_IP '/opt/ottochain/scripts/start-all.sh'"
