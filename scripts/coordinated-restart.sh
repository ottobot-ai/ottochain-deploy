#!/bin/bash
# coordinated-restart.sh - Coordinated restart of metagraph layers
#
# Handles the fresh-start deadlock by:
# 1. Stopping all layers in reverse order
# 2. Optionally wiping state
# 3. Starting GL0 genesis, waiting for Ready
# 4. Starting GL0 validators, joining cluster
# 5. Waiting for GL0 cluster (3 Ready)
# 6. Starting remaining layers in order
#
# Usage:
#   ./coordinated-restart.sh                    # Restart all layers (no wipe)
#   ./coordinated-restart.sh --wipe             # Wipe all state, fresh genesis
#   ./coordinated-restart.sh --layer gl0        # Restart only GL0 cluster
#   ./coordinated-restart.sh --check            # Check if restart needed
#
# Environment:
#   GENESIS_IP       - IP of genesis node (default: auto-detect)
#   NODES            - Space-separated IPs of all nodes
#   SSH_KEY          - Path to SSH key for remote nodes

set -euo pipefail

# Configuration
GENESIS_IP="${GENESIS_IP:-}"
NODES="${NODES:-}"
SSH_KEY="${SSH_KEY:-/root/.ssh/id_rsa}"
WIPE="${WIPE:-false}"
LAYER="${LAYER:-all}"
CHECK_ONLY="${CHECK_ONLY:-false}"

# Timeouts
READY_TIMEOUT=120
CLUSTER_TIMEOUT=180

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
err() { log "ERROR: $*" >&2; }

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --wipe) WIPE=true; shift ;;
    --layer) LAYER="$2"; shift 2 ;;
    --check) CHECK_ONLY=true; shift ;;
    --genesis-ip) GENESIS_IP="$2"; shift 2 ;;
    --nodes) NODES="$2"; shift 2 ;;
    --ssh-key) SSH_KEY="$2"; shift 2 ;;
    *) err "Unknown option: $1"; exit 1 ;;
  esac
done

# Auto-detect configuration if not provided
if [[ -z "$GENESIS_IP" ]]; then
  # Assume we're running on genesis
  GENESIS_IP=$(hostname -I | awk '{print $1}')
fi

run_local() {
  eval "$@"
}

run_remote() {
  local ip=$1
  shift
  if [[ "$ip" = "$GENESIS_IP" ]] || [[ "$ip" = "localhost" ]]; then
    run_local "$@"
  else
    ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@${ip}" "$@"
  fi
}

wait_for_ready() {
  local ip=$1
  local layer=$2
  local port=$3
  local timeout=$4
  
  log "Waiting for $layer on $ip to become Ready..."
  for i in $(seq 1 $((timeout / 5))); do
    local state=$(run_remote "$ip" "curl -sf http://localhost:${port}/node/info | jq -r .state" 2>/dev/null || echo "")
    if [[ "$state" = "Ready" ]]; then
      log "$layer on $ip is Ready"
      return 0
    fi
    sleep 5
  done
  
  err "$layer on $ip did not become Ready within ${timeout}s"
  return 1
}

wait_for_cluster() {
  local ip=$1
  local port=$2
  local count=$3
  local timeout=$4
  
  log "Waiting for cluster to have $count Ready nodes..."
  for i in $(seq 1 $((timeout / 5))); do
    local ready=$(run_remote "$ip" "curl -sf http://localhost:${port}/cluster/info | jq '[.[] | select(.state == \"Ready\")] | length'" 2>/dev/null || echo "0")
    if [[ "$ready" -ge "$count" ]]; then
      log "Cluster has $ready Ready nodes"
      return 0
    fi
    log "Cluster Ready: $ready/$count (attempt $i)"
    sleep 5
  done
  
  err "Cluster did not reach $count Ready nodes within ${timeout}s"
  return 1
}

get_peer_id() {
  local ip=$1
  local port=$2
  run_remote "$ip" "curl -sf http://localhost:${port}/node/info | jq -r .id"
}

join_cluster() {
  local validator_ip=$1
  local genesis_id=$2
  local genesis_ip=$3
  local cli_port=$4
  local p2p_port=$5
  
  log "Joining $validator_ip to cluster..."
  run_remote "$validator_ip" "docker exec gl0 curl -sf -X POST http://127.0.0.1:${cli_port}/cluster/join \
    -H 'Content-Type: application/json' \
    -d '{\"id\": \"${genesis_id}\", \"ip\": \"${genesis_ip}\", \"p2pPort\": ${p2p_port}}'" || true
}

stop_layer() {
  local ip=$1
  local layer=$2
  log "Stopping $layer on $ip..."
  run_remote "$ip" "docker stop $layer 2>/dev/null" || true
}

start_layer() {
  local ip=$1
  local layer=$2
  log "Starting $layer on $ip..."
  run_remote "$ip" "docker start $layer"
}

wipe_layer_data() {
  local ip=$1
  local layer=$2
  local data_dir="/opt/ottochain/${layer}-data"
  
  log "Wiping $layer data on $ip..."
  run_remote "$ip" "rm -rf ${data_dir}/*"
}

check_deadlock() {
  log "Checking for fresh-start deadlock..."
  
  local cluster=$(curl -sf http://localhost:9000/cluster/info 2>/dev/null || echo "[]")
  local ready=$(echo "$cluster" | jq '[.[] | select(.state == "Ready")] | length' 2>/dev/null || echo "0")
  local stuck=$(echo "$cluster" | jq '[.[] | select(.state | test("WaitingForDownload|DownloadInProgress"))] | length' 2>/dev/null || echo "0")
  local ordinal=$(curl -sf http://localhost:9000/global-snapshots/latest 2>/dev/null | jq -r '.value.ordinal // 0' || echo "0")
  
  log "GL0 cluster: Ready=$ready, Stuck=$stuck, Ordinal=$ordinal"
  
  if [[ "$ready" = "1" ]] && [[ "$stuck" -ge 2 ]] && [[ "$ordinal" = "0" || "$ordinal" = "null" ]]; then
    log "DEADLOCK DETECTED: Fresh-start deadlock"
    return 0
  fi
  
  log "No deadlock detected"
  return 1
}

restart_gl0_cluster() {
  log "=== Coordinated GL0 Cluster Restart ==="
  
  # Get node list (if not provided, assume we're on genesis and others are validators)
  local nodes=($NODES)
  if [[ ${#nodes[@]} -eq 0 ]]; then
    # Try to get from cluster info
    local cluster=$(curl -sf http://localhost:9000/cluster/info 2>/dev/null || echo "[]")
    nodes=($(echo "$cluster" | jq -r '.[].ip' 2>/dev/null | sort -u))
  fi
  
  if [[ ${#nodes[@]} -eq 0 ]]; then
    nodes=("$GENESIS_IP")
  fi
  
  log "Nodes: ${nodes[*]}"
  
  # 1. Stop all GL0 containers
  log "Step 1: Stopping GL0 on all nodes..."
  for ip in "${nodes[@]}"; do
    stop_layer "$ip" "gl0" &
  done
  wait
  
  # 2. Wipe if requested
  if [[ "$WIPE" = "true" ]]; then
    log "Step 2: Wiping GL0 data..."
    for ip in "${nodes[@]}"; do
      wipe_layer_data "$ip" "gl0" &
    done
    wait
  fi
  
  # 3. Start genesis
  log "Step 3: Starting GL0 genesis..."
  start_layer "$GENESIS_IP" "gl0"
  
  # 4. Wait for genesis Ready
  wait_for_ready "$GENESIS_IP" "gl0" 9000 "$READY_TIMEOUT" || return 1
  
  # 5. Get genesis peer ID
  local genesis_id=$(get_peer_id "$GENESIS_IP" 9000)
  log "Genesis peer ID: ${genesis_id:0:16}..."
  
  # 6. Start validators
  log "Step 4: Starting GL0 validators..."
  for ip in "${nodes[@]}"; do
    if [[ "$ip" != "$GENESIS_IP" ]]; then
      start_layer "$ip" "gl0"
    fi
  done
  
  sleep 10
  
  # 7. Join validators to cluster
  log "Step 5: Joining validators to cluster..."
  for ip in "${nodes[@]}"; do
    if [[ "$ip" != "$GENESIS_IP" ]]; then
      join_cluster "$ip" "$genesis_id" "$GENESIS_IP" 9002 9001
    fi
  done
  
  # 8. Wait for cluster
  wait_for_cluster "$GENESIS_IP" 9000 "${#nodes[@]}" "$CLUSTER_TIMEOUT" || return 1
  
  log "=== GL0 Cluster Restart Complete ==="
}

restart_all() {
  log "=== Full Coordinated Restart ==="
  
  local nodes=($NODES)
  if [[ ${#nodes[@]} -eq 0 ]]; then
    nodes=("$GENESIS_IP")
  fi
  
  # 1. Stop all layers in reverse order
  log "Stopping all layers..."
  for layer in dl1 cl1 gl1 ml0 gl0; do
    for ip in "${nodes[@]}"; do
      stop_layer "$ip" "$layer" &
    done
    wait
  done
  
  # 2. Wipe if requested
  if [[ "$WIPE" = "true" ]]; then
    log "Wiping all state..."
    for layer in gl0 gl1 ml0 cl1 dl1; do
      for ip in "${nodes[@]}"; do
        wipe_layer_data "$ip" "$layer" &
      done
      wait
    done
  fi
  
  # 3. Restart GL0 cluster
  restart_gl0_cluster || return 1
  
  # 4. Get GL0 peer info for dependent layers
  local gl0_id=$(get_peer_id "$GENESIS_IP" 9000)
  
  # 5. Start ML0 (needs GL0)
  log "Starting ML0..."
  for ip in "${nodes[@]}"; do
    start_layer "$ip" "ml0"
  done
  sleep 30
  
  # 6. Start GL1, CL1, DL1
  log "Starting L1 layers..."
  for layer in gl1 cl1 dl1; do
    for ip in "${nodes[@]}"; do
      start_layer "$ip" "$layer"
    done
  done
  
  log "=== Full Restart Complete ==="
}

# Main
if [[ "$CHECK_ONLY" = "true" ]]; then
  if check_deadlock; then
    log "Recommendation: Run with --wipe to resolve deadlock"
    exit 1
  fi
  exit 0
fi

case "$LAYER" in
  gl0)
    restart_gl0_cluster
    ;;
  all)
    restart_all
    ;;
  *)
    err "Unknown layer: $LAYER"
    exit 1
    ;;
esac
