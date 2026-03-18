#!/usr/bin/env bash
# Join validator nodes to a running cluster
# Usage: join-cluster.sh <layer> <genesis_ip> <genesis_peer_id> <validator_ips...>
#
# Example:
#   join-cluster.sh gl0 5.78.90.207 abc123... 5.78.113.25 5.78.107.77

set -euo pipefail

LAYER="${1:?Usage: join-cluster.sh <layer> <genesis_ip> <genesis_peer_id> <validator_ips...>}"
GENESIS_IP="${2:?Genesis IP required}"
GENESIS_PEER_ID="${3:?Genesis peer ID required}"
shift 3
VALIDATOR_IPS=("$@")

# Port mapping per layer
case "$LAYER" in
  gl0) PUBLIC=9000; P2P=9001; CLI=9002 ;;
  gl1) PUBLIC=9100; P2P=9101; CLI=9102 ;;
  ml0) PUBLIC=9200; P2P=9201; CLI=9202 ;;
  cl1) PUBLIC=9300; P2P=9301; CLI=9302 ;;
  dl1) PUBLIC=9400; P2P=9401; CLI=9402 ;;
  *)   echo "Unknown layer: $LAYER"; exit 1 ;;
esac

echo "=== Joining ${LAYER^^} cluster ==="
echo "Genesis: $GENESIS_IP (${GENESIS_PEER_ID:0:16}...)"
echo "Validators: ${VALIDATOR_IPS[*]}"

# Wait for genesis node to be Ready
echo "Waiting for genesis node..."
for i in $(seq 1 60); do
  state=$(curl -sf --max-time 3 "http://${GENESIS_IP}:${PUBLIC}/node/state" 2>/dev/null | tr -d '"' || echo "")
  if [ "$state" = "Ready" ]; then
    echo "✓ Genesis node Ready"
    break
  fi
  if [ "$i" = "60" ]; then
    echo "❌ Genesis node not Ready after 5 minutes"
    exit 1
  fi
  sleep 5
done

# Wait for each validator to reach ReadyToJoin, then join
for ip in "${VALIDATOR_IPS[@]}"; do
  echo ""
  echo "--- Joining $ip ---"
  
  # Wait for ReadyToJoin
  for i in $(seq 1 60); do
    state=$(curl -sf --max-time 3 "http://${ip}:${PUBLIC}/node/state" 2>/dev/null | tr -d '"' || echo "")
    if [ "$state" = "ReadyToJoin" ]; then
      echo "  ✓ $ip reached ReadyToJoin"
      break
    fi
    if [ "$i" = "60" ]; then
      echo "  ❌ $ip did not reach ReadyToJoin after 5 minutes (state: $state)"
      continue 2  # Skip to next validator
    fi
    sleep 5
  done
  
  # Send join request
  RESPONSE=$(curl -sf --max-time 15 -X POST "http://${ip}:${CLI}/cluster/join" \
    -H 'Content-Type: application/json' \
    -d "{\"id\": \"${GENESIS_PEER_ID}\", \"ip\": \"${GENESIS_IP}\", \"p2pPort\": ${P2P}}" 2>&1 || echo "FAILED")
  
  if [ "$RESPONSE" = "FAILED" ]; then
    echo "  ⚠️ Join request failed for $ip — may need retry"
  else
    echo "  ✓ Join request sent to $ip"
  fi
done

# Wait for cluster to form
echo ""
echo "--- Verifying cluster formation ---"
sleep 15
CLUSTER_SIZE=$(curl -sf --max-time 5 "http://${GENESIS_IP}:${PUBLIC}/cluster/info" 2>/dev/null | jq length 2>/dev/null || echo "0")
EXPECTED=$((${#VALIDATOR_IPS[@]} + 1))
echo "Cluster size: $CLUSTER_SIZE (expected: $EXPECTED)"

if [ "$CLUSTER_SIZE" -ge "$EXPECTED" ]; then
  echo "✅ ${LAYER^^} cluster formed with $CLUSTER_SIZE nodes"
else
  echo "⚠️ ${LAYER^^} cluster has $CLUSTER_SIZE/$EXPECTED nodes — some may still be joining"
fi
