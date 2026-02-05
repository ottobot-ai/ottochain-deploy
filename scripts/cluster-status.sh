#!/bin/bash
# Check status of all OttoChain cluster nodes
set -e

declare -A NODE_IPS=(
  ["node1"]="5.78.90.207"
  ["node2"]="5.78.113.25"
  ["node3"]="5.78.107.77"
)

echo "=== OttoChain Cluster Status ==="
echo ""

for node in node1 node2 node3; do
  ip="${NODE_IPS[$node]}"
  echo "--- $node ($ip) ---"
  
  for svc in gl0:9000 ml0:9200 cl1:9300 dl1:9400; do
    name="${svc%%:*}"
    port="${svc##*:}"
    
    INFO=$(curl -s --connect-timeout 3 "http://$ip:$port/node/info" 2>/dev/null)
    if [ -n "$INFO" ]; then
      STATE=$(echo "$INFO" | jq -r '.state // "unknown"')
      ID=$(echo "$INFO" | jq -r '.id // "?"' | cut -c1-16)
      printf "  %-4s: %-10s (ID: %s...)\n" "$name" "$STATE" "$ID"
    else
      printf "  %-4s: %-10s\n" "$name" "DOWN"
    fi
  done
  echo ""
done

# Check cluster info from GL0
echo "--- Cluster Overview ---"
GL0_CLUSTER=$(curl -s --connect-timeout 3 "http://${NODE_IPS[node1]}:9000/cluster/info" 2>/dev/null)
if [ -n "$GL0_CLUSTER" ]; then
  PEER_COUNT=$(echo "$GL0_CLUSTER" | jq -r 'length // 0')
  echo "GL0 cluster peers: $PEER_COUNT"
fi

ML0_SNAPSHOTS=$(curl -s --connect-timeout 3 "http://${NODE_IPS[node1]}:9200/snapshots/latest" 2>/dev/null)
if [ -n "$ML0_SNAPSHOTS" ]; then
  ORDINAL=$(echo "$ML0_SNAPSHOTS" | jq -r '.value.ordinal // 0')
  echo "Latest ML0 snapshot ordinal: $ORDINAL"
fi
