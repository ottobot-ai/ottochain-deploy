#!/bin/bash
# Node hardening for OttoChain metagraph nodes
# Idempotent — safe to run multiple times
# Run after first-time-setup.sh, or standalone on existing nodes
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../inventory.sh" 2>/dev/null || true

SSH_KEY="${SSH_KEY:-$HOME/.ssh/hetzner_ottobot}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $SSH_KEY"

SWAP_SIZE="${SWAP_SIZE:-8G}"

usage() {
    echo "Usage: $0 <node_number|services|all>"
    echo ""
    echo "  node_number: 1, 2, or 3 (metagraph nodes, 16GB RAM)"
    echo "  services:    services node (8GB RAM, uses 4G swap)"
    echo "  all:         all nodes including services"
    echo ""
    echo "Environment:"
    echo "  SWAP_SIZE=8G   Swap file size (default: 8G, services uses 4G)"
    exit 1
}

harden_node() {
    local label=$1
    local node_ip=$2
    local swap_size=$3

    echo "============================================"
    echo "Hardening: $label ($node_ip) — swap=${swap_size}"
    echo "============================================"

    ssh $SSH_OPTS root@$node_ip << HARDEN_SCRIPT
set -e

echo "=== Swap setup ==="
if swapon --show | grep -q /swapfile; then
    echo "Swap already active: \$(swapon --show)"
else
    if [ -f /swapfile ]; then
        echo "Swapfile exists but not active, activating..."
    else
        echo "Creating ${swap_size} swapfile..."
        fallocate -l ${swap_size} /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
    fi
    swapon /swapfile
    echo "Swap activated: \$(swapon --show)"
fi

# Persist swap across reboots
if ! grep -q '/swapfile' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "Added swap to /etc/fstab"
fi

echo ""
echo "=== Kernel tuning ==="
# Low swappiness — only use swap under real pressure
if ! grep -q 'vm.swappiness=10' /etc/sysctl.conf; then
    echo 'vm.swappiness=10' >> /etc/sysctl.conf
fi
sysctl -w vm.swappiness=10 > /dev/null

# Don't OOM-kill too aggressively
if ! grep -q 'vm.overcommit_memory=0' /etc/sysctl.conf; then
    echo 'vm.overcommit_memory=0' >> /etc/sysctl.conf
fi
sysctl -w vm.overcommit_memory=0 > /dev/null

# Increase max open files for JVMs
if ! grep -q '* soft nofile 65536' /etc/security/limits.conf; then
    echo '* soft nofile 65536' >> /etc/security/limits.conf
    echo '* hard nofile 65536' >> /etc/security/limits.conf
    echo "Increased file descriptor limits"
fi

echo "Kernel params: swappiness=\$(cat /proc/sys/vm/swappiness), overcommit=\$(cat /proc/sys/vm/overcommit_memory)"

echo ""
echo "=== Docker daemon tuning ==="
DOCKER_CONF=/etc/docker/daemon.json
if [ ! -f "\$DOCKER_CONF" ] || ! grep -q 'log-opts' "\$DOCKER_CONF"; then
    cat > "\$DOCKER_CONF" << 'DOCKER_JSON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  },
  "default-ulimits": {
    "nofile": { "Name": "nofile", "Hard": 65536, "Soft": 65536 }
  }
}
DOCKER_JSON
    systemctl restart docker
    echo "Docker log rotation configured (50MB × 3 files)"
else
    echo "Docker daemon.json already configured"
fi

echo ""
echo "=== Node exporter ==="
if docker ps --format '{{.Names}}' | grep -q node-exporter; then
    echo "Node exporter already running"
else
    echo "Starting node exporter..."
    docker run -d --name node-exporter \
        --restart=unless-stopped \
        --net=host \
        --pid=host \
        -v /:/host:ro,rslave \
        prom/node-exporter:latest \
        --path.rootfs=/host 2>/dev/null || \
    docker start node-exporter 2>/dev/null || \
    echo "Node exporter container exists, may need manual check"
fi

echo ""
echo "=== Verify ==="
echo "Swap:       \$(free -h | grep Swap | awk '{print \$2}')"
echo "RAM:        \$(free -h | grep Mem | awk '{print \$2}')"
echo "Swappiness: \$(cat /proc/sys/vm/swappiness)"
echo "Docker:     \$(docker --version 2>/dev/null || echo 'not found')"
echo "Exporter:   \$(docker ps --filter name=node-exporter --format '{{.Status}}' 2>/dev/null || echo 'not running')"
echo ""
echo "✓ Hardening complete for $label"
HARDEN_SCRIPT
}

# Parse args
TARGET="${1:-}"
[[ -z "$TARGET" ]] && usage

case "$TARGET" in
    1)       harden_node "node1" "${NODE1_IP}" "$SWAP_SIZE" ;;
    2)       harden_node "node2" "${NODE2_IP}" "$SWAP_SIZE" ;;
    3)       harden_node "node3" "${NODE3_IP}" "$SWAP_SIZE" ;;
    services) harden_node "services" "${SERVICES_IP}" "4G" ;;
    all)
        harden_node "node1" "${NODE1_IP}" "$SWAP_SIZE"
        harden_node "node2" "${NODE2_IP}" "$SWAP_SIZE"
        harden_node "node3" "${NODE3_IP}" "$SWAP_SIZE"
        harden_node "services" "${SERVICES_IP}" "4G"
        ;;
    *)       usage ;;
esac

echo ""
echo "============================================"
echo "Hardening complete!"
echo "============================================"
