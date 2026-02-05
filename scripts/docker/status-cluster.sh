#!/bin/bash
# Check status of OttoChain Docker cluster
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../inventory.sh" 2>/dev/null || true

NODE1_IP="${NODE1_IP:-5.78.90.207}"
NODE2_IP="${NODE2_IP:-5.78.113.25}"
NODE3_IP="${NODE3_IP:-5.78.107.77}"

NODES=("$NODE1_IP" "$NODE2_IP" "$NODE3_IP")

check_layer() {
    local ip=$1
    local port=$2
    local name=$3
    
    local result=$(curl -sf "http://$ip:$port/node/info" 2>/dev/null)
    if [[ -n "$result" ]]; then
        local state=$(echo "$result" | jq -r '.state // "unknown"')
        case "$state" in
            Ready) echo -e "  $name:\t\e[32m$state\e[0m" ;;
            *)     echo -e "  $name:\t\e[33m$state\e[0m" ;;
        esac
    else
        echo -e "  $name:\t\e[31mDOWN\e[0m"
    fi
}

check_cluster_size() {
    local ip=$1
    local port=$2
    local name=$3
    
    local size=$(curl -sf "http://$ip:$port/cluster/info" 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
    echo "  $name cluster: $size nodes"
}

echo "============================================"
echo "OttoChain Cluster Status"
echo "============================================"

for i in "${!NODES[@]}"; do
    node_num=$((i + 1))
    node_ip="${NODES[$i]}"
    echo ""
    echo "Node $node_num ($node_ip):"
    
    check_layer $node_ip 9000 "GL0"
    check_layer $node_ip 9100 "GL1"
    check_layer $node_ip 9200 "ML0"
    check_layer $node_ip 9300 "CL1"
    check_layer $node_ip 9400 "DL1"
done

echo ""
echo "============================================"
echo "Cluster Formation"
echo "============================================"
check_cluster_size $NODE1_IP 9000 "GL0"
check_cluster_size $NODE1_IP 9100 "GL1"
check_cluster_size $NODE1_IP 9200 "ML0"
check_cluster_size $NODE1_IP 9300 "CL1"
check_cluster_size $NODE1_IP 9400 "DL1"

echo ""
