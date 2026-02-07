#!/bin/bash
# First-time setup for OttoChain nodes
# Run this once per node to install Docker and generate keys
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../inventory.sh" 2>/dev/null || true

SSH_KEY="${SSH_KEY:-$HOME/.ssh/hetzner_ottobot}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $SSH_KEY"

usage() {
    echo "Usage: $0 [node_number|all]"
    echo ""
    echo "  node_number: 1, 2, or 3"
    echo "  all: setup all nodes"
    echo ""
    echo "This script:"
    echo "  1. Installs Docker if not present"
    echo "  2. Creates /opt/ottochain directory structure"
    echo "  3. Generates a keystore if not present"
    exit 1
}

setup_node() {
    local node_num=$1
    local node_ip=$2
    
    echo "============================================"
    echo "Setting up Node $node_num ($node_ip)"
    echo "============================================"
    
    ssh $SSH_OPTS root@$node_ip << 'SETUP_SCRIPT'
set -e

echo "=== Checking Docker ==="
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
    systemctl enable docker
    systemctl start docker
    echo "Docker installed"
else
    echo "Docker already installed: $(docker --version)"
fi

echo ""
echo "=== Creating directory structure ==="
mkdir -p /opt/ottochain/{keys,jars,data,logs,genesis}
chmod 700 /opt/ottochain/keys

echo ""
echo "=== Checking for keystore ==="
if [ -f /opt/ottochain/keys/key.p12 ]; then
    echo "Keystore already exists at /opt/ottochain/keys/key.p12"
else
    echo "No keystore found. You'll need to either:"
    echo "  1. Copy an existing keystore: scp your-key.p12 root@$(hostname -I | awk '{print $1}'):/opt/ottochain/keys/key.p12"
    echo "  2. Generate one using tessellation keytool (see docs)"
fi

echo ""
echo "=== Installing utilities ==="
apt-get install -y jq curl

echo ""
echo "=== Node setup complete ==="
echo "Directory structure:"
ls -la /opt/ottochain/
SETUP_SCRIPT

    echo ""
    echo "✓ Node $node_num setup complete"
}

# Parse args
TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
    usage
fi

case "$TARGET" in
    1)
        setup_node 1 "${NODE1_IP:-${NODE1_IP}}"
        ;;
    2)
        setup_node 2 "${NODE2_IP:-${NODE2_IP}}"
        ;;
    3)
        setup_node 3 "${NODE3_IP:-${NODE3_IP}}"
        ;;
    all)
        setup_node 1 "${NODE1_IP:-${NODE1_IP}}"
        setup_node 2 "${NODE2_IP:-${NODE2_IP}}"
        setup_node 3 "${NODE3_IP:-${NODE3_IP}}"
        ;;
    *)
        usage
        ;;
esac

echo ""
echo "============================================"
echo "Setup complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Ensure keystores exist at /opt/ottochain/keys/key.p12 on each node"
echo "  2. Run: ./scripts/deploy-node.sh <node_num>"
echo "  3. Run: ./scripts/start-cluster.sh"
