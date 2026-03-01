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

echo "=== SSH hardening ==="
SSHD_CONFIG=/etc/ssh/sshd_config
SSHD_CHANGED=false

# Disable password auth (key-only)
if grep -q '^PasswordAuthentication yes' \$SSHD_CONFIG 2>/dev/null; then
    sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' \$SSHD_CONFIG
    SSHD_CHANGED=true
elif ! grep -q '^PasswordAuthentication' \$SSHD_CONFIG; then
    echo 'PasswordAuthentication no' >> \$SSHD_CONFIG
    SSHD_CHANGED=true
fi

# Disable root password login (keep key auth)
if grep -q '^PermitRootLogin yes' \$SSHD_CONFIG 2>/dev/null; then
    sed -i 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' \$SSHD_CONFIG
    SSHD_CHANGED=true
elif ! grep -q '^PermitRootLogin' \$SSHD_CONFIG; then
    echo 'PermitRootLogin prohibit-password' >> \$SSHD_CONFIG
    SSHD_CHANGED=true
fi

# Reduce max auth tries
if ! grep -q '^MaxAuthTries' \$SSHD_CONFIG; then
    echo 'MaxAuthTries 3' >> \$SSHD_CONFIG
    SSHD_CHANGED=true
fi

if [ "\$SSHD_CHANGED" = "true" ]; then
    systemctl reload sshd
    echo "SSH hardened: password auth disabled, root login key-only, max 3 auth tries"
else
    echo "SSH already hardened"
fi

echo ""
echo "=== fail2ban ==="
if ! command -v fail2ban-server &> /dev/null; then
    apt-get update -qq
    apt-get install -y -qq fail2ban
fi

# Configure jail
cat > /etc/fail2ban/jail.local << 'F2B'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400
F2B

systemctl enable fail2ban
systemctl restart fail2ban
echo "fail2ban active: \$(fail2ban-client status sshd 2>/dev/null | grep 'Currently banned' || echo 'starting...')"

echo ""
echo "=== UFW firewall ==="
if ! command -v ufw &> /dev/null; then
    apt-get install -y -qq ufw
fi

# Only configure if UFW is inactive (don't overwrite existing rules)
if ufw status | grep -q "inactive"; then
    ufw default deny incoming
    ufw default allow outgoing

    # SSH (always)
    ufw allow 22/tcp

    if [ "$label" = "services" ]; then
        # Services node ports
        ufw allow 3030/tcp   # Bridge
        ufw allow 3031/tcp   # Indexer
        ufw allow 4000/tcp   # Gateway
        ufw allow 8080/tcp   # Explorer
        ufw allow 9090/tcp   # Prometheus
        ufw allow 3000/tcp   # Grafana
        ufw allow 9100/tcp   # Node exporter
        ufw allow 9093/tcp   # Alertmanager
        echo "UFW enabled with services node rules"
    else
        # Metagraph node ports — Tessellation public API
        ufw allow 9000/tcp   # GL0
        ufw allow 9100/tcp   # GL1
        ufw allow 9200/tcp   # ML0
        ufw allow 9300/tcp   # CL1
        ufw allow 9400/tcp   # DL1

        # Tessellation P2P ports
        ufw allow 9001/tcp   # GL0 P2P
        ufw allow 9101/tcp   # GL1 P2P
        ufw allow 9201/tcp   # ML0 P2P
        ufw allow 9301/tcp   # CL1 P2P
        ufw allow 9401/tcp   # DL1 P2P
        echo "UFW enabled with tessellation + SSH rules"
    fi

    # Enable (--force to skip interactive prompt)
    ufw --force enable
else
    echo "UFW already active, not modifying rules"
fi

echo ""
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
    if docker run -d --name node-exporter \
        --restart=unless-stopped \
        --net=host \
        --pid=host \
        -v /:/host:ro,rslave \
        prom/node-exporter:latest \
        --path.rootfs=/host 2>&1; then
        echo "Node exporter started"
    elif docker start node-exporter 2>&1; then
        echo "Node exporter restarted"
    else
        echo "WARNING: Failed to start node exporter — check manually"
    fi
fi

echo ""
echo "=== Verify ==="
echo "Swap:       \$(free -h | grep Swap | awk '{print \$2}')"
echo "RAM:        \$(free -h | grep Mem | awk '{print \$2}')"
echo "Swappiness: \$(cat /proc/sys/vm/swappiness)"
echo "Docker:     \$(docker --version 2>/dev/null || echo 'not found')"
echo "Exporter:   \$(docker ps --filter name=node-exporter --format '{{.Status}}' 2>/dev/null || echo 'not running')"
echo "fail2ban: \$(systemctl is-active fail2ban 2>/dev/null || echo 'not running')"
echo "UFW:      \$(ufw status | head -1)"
echo "SSH:      PasswordAuth=\$(grep '^PasswordAuthentication' /etc/ssh/sshd_config 2>/dev/null || echo 'default')"
echo ""
echo "✓ Hardening complete for $label"
HARDEN_SCRIPT
}

# Parse args
TARGET="${1:-}"
[[ -z "$TARGET" ]] && usage

require_ip() {
    local name=$1 val=$2
    if [[ -z "$val" ]]; then
        echo "Error: ${name} not set. Source inventory.sh or export it." >&2
        exit 1
    fi
}

case "$TARGET" in
    1)       require_ip NODE1_IP "$NODE1_IP"; harden_node "node1" "${NODE1_IP}" "$SWAP_SIZE" ;;
    2)       require_ip NODE2_IP "$NODE2_IP"; harden_node "node2" "${NODE2_IP}" "$SWAP_SIZE" ;;
    3)       require_ip NODE3_IP "$NODE3_IP"; harden_node "node3" "${NODE3_IP}" "$SWAP_SIZE" ;;
    services) require_ip SERVICES_IP "$SERVICES_IP"; harden_node "services" "${SERVICES_IP}" "4G" ;;
    all)
        require_ip NODE1_IP "$NODE1_IP"
        require_ip NODE2_IP "$NODE2_IP"
        require_ip NODE3_IP "$NODE3_IP"
        require_ip SERVICES_IP "$SERVICES_IP"
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
