#!/bin/bash
# layer-watchdog-v2.sh - Robust metagraph layer monitoring with state-aware restarts
#
# Improvements over v1:
# - Detects stuck states (WaitingForDownload, Leaving, Offline)
# - Tracks restart loops and alerts instead of thrashing
# - Coordinated restart option for GL0 cluster reset
# - Genesis ordinal 0 detection (fresh start deadlock)
#
# Usage:
#   ./layer-watchdog-v2.sh              # Single check all layers
#   ./layer-watchdog-v2.sh --daemon     # Continuous monitoring
#   ./layer-watchdog-v2.sh --status     # Show current state
#
# Cron (recommended):
#   */2 * * * * /opt/ottochain/scripts/layer-watchdog-v2.sh >> /var/log/layer-watchdog.log 2>&1

set -euo pipefail

STATE_FILE="/tmp/layer-watchdog-state.json"
RESTART_LOG="/tmp/layer-watchdog-restarts.log"

# Thresholds
STALL_THRESHOLD_MINUTES="${STALL_THRESHOLD_MINUTES:-5}"
STUCK_STATE_THRESHOLD_MINUTES="${STUCK_STATE_THRESHOLD_MINUTES:-3}"
COOLDOWN_MINUTES="${COOLDOWN_MINUTES:-10}"
MAX_RESTARTS_PER_HOUR="${MAX_RESTARTS_PER_HOUR:-6}"
DAEMON_INTERVAL="${DAEMON_INTERVAL:-120}"

# Alert webhook (optional)
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"

# Layer config
declare -A LAYER_PORTS=(
  ["gl0"]=9000
  ["ml0"]=9200
  ["cl1"]=9300
  ["dl1"]=9400
)

declare -A LAYER_ORDINAL_ENDPOINTS=(
  ["gl0"]="/global-snapshots/latest"
  ["ml0"]="/snapshots/latest"
  ["cl1"]="/snapshots/latest"
  ["dl1"]="/data/latest"
)

# Stuck states that indicate problems
STUCK_STATES="WaitingForDownload|Leaving|Offline|DownloadInProgress"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

init_state() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo '{}' > "$STATE_FILE"
  fi
}

get_state() {
  local layer=$1 field=$2
  jq -r --arg l "$layer" --arg f "$field" '.[$l][$f] // empty' "$STATE_FILE"
}

set_state() {
  local layer=$1 field=$2 value=$3
  local tmp=$(mktemp)
  jq --arg l "$layer" --arg f "$field" --arg v "$value" \
    '.[$l] //= {} | .[$l][$f] = ($v | tonumber? // $v)' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

get_ordinal() {
  local layer=$1
  local port="${LAYER_PORTS[$layer]}"
  local endpoint="${LAYER_ORDINAL_ENDPOINTS[$layer]}"
  
  local result
  result=$(curl -sf --max-time 5 "http://localhost:${port}${endpoint}" 2>/dev/null) || { echo "-1"; return; }
  
  local ordinal
  ordinal=$(echo "$result" | jq -r '.value.ordinal // .ordinal // -1' 2>/dev/null) || ordinal=-1
  echo "$ordinal"
}

get_node_state() {
  local layer=$1
  local port="${LAYER_PORTS[$layer]}"
  curl -sf --max-time 5 "http://localhost:${port}/node/info" 2>/dev/null | jq -r '.state // "Unknown"' || echo "Unreachable"
}

get_cluster_info() {
  local layer=$1
  local port="${LAYER_PORTS[$layer]}"
  curl -sf --max-time 5 "http://localhost:${port}/cluster/info" 2>/dev/null || echo "[]"
}

is_container_running() {
  docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${1}$"
}

count_recent_restarts() {
  local layer=$1
  local one_hour_ago=$(($(date +%s) - 3600))
  
  if [[ ! -f "$RESTART_LOG" ]]; then
    echo "0"
    return
  fi
  
  grep "^${layer}:" "$RESTART_LOG" 2>/dev/null | while read line; do
    ts=$(echo "$line" | cut -d: -f2)
    if [[ "$ts" -gt "$one_hour_ago" ]]; then
      echo "1"
    fi
  done | wc -l
}

log_restart() {
  local layer=$1
  echo "${layer}:$(date +%s)" >> "$RESTART_LOG"
  
  # Trim old entries (keep last 100)
  if [[ -f "$RESTART_LOG" ]]; then
    tail -100 "$RESTART_LOG" > "${RESTART_LOG}.tmp" && mv "${RESTART_LOG}.tmp" "$RESTART_LOG"
  fi
}

send_alert() {
  local message=$1
  log "ALERT: $message"
  
  if [[ -n "$ALERT_WEBHOOK" ]]; then
    curl -sf -X POST "$ALERT_WEBHOOK" \
      -H "Content-Type: application/json" \
      -d "{\"text\": \"🚨 Layer Watchdog: $message\"}" >/dev/null 2>&1 || true
  fi
}

restart_layer() {
  local layer=$1
  local reason=$2
  
  # Check restart rate limit
  local recent=$(count_recent_restarts "$layer")
  if [[ "$recent" -ge "$MAX_RESTARTS_PER_HOUR" ]]; then
    send_alert "$layer restart loop detected ($recent restarts in 1h). Manual intervention required."
    return 1
  fi
  
  log "RESTART: Restarting $layer (reason: $reason)..."
  
  if docker restart "$layer" 2>/dev/null; then
    log "RESTART: $layer restarted successfully"
    set_state "$layer" "last_restart" "$(date +%s)"
    log_restart "$layer"
    return 0
  else
    log "ERROR: Failed to restart $layer"
    return 1
  fi
}

check_fresh_start_deadlock() {
  # Detect the fresh-start deadlock:
  # - GL0 genesis at ordinal 0
  # - Validators stuck in WaitingForDownload/DownloadInProgress
  # - No progress possible
  
  local cluster_info=$(get_cluster_info "gl0")
  local ready_count=$(echo "$cluster_info" | jq '[.[] | select(.state == "Ready")] | length' 2>/dev/null || echo "0")
  local total_count=$(echo "$cluster_info" | jq 'length' 2>/dev/null || echo "0")
  local stuck_count=$(echo "$cluster_info" | jq '[.[] | select(.state | test("WaitingForDownload|DownloadInProgress"))] | length' 2>/dev/null || echo "0")
  
  local ordinal=$(get_ordinal "gl0")
  
  if [[ "$ready_count" = "1" ]] && [[ "$stuck_count" -ge 2 ]] && [[ "$ordinal" = "0" || "$ordinal" = "-1" ]]; then
    log "DEADLOCK: Fresh-start deadlock detected (1 Ready, $stuck_count stuck, ordinal=$ordinal)"
    send_alert "Fresh-start deadlock: GL0 genesis at ordinal 0, validators stuck. Need coordinated restart with wipe."
    return 0
  fi
  
  return 1
}

check_layer() {
  local layer=$1
  local now=$(date +%s)
  local stall_sec=$((STALL_THRESHOLD_MINUTES * 60))
  local stuck_sec=$((STUCK_STATE_THRESHOLD_MINUTES * 60))
  local cooldown_sec=$((COOLDOWN_MINUTES * 60))
  
  # Skip if container not running
  if ! is_container_running "$layer"; then
    log "SKIP: $layer container not running"
    return 0
  fi
  
  # Get current state
  local node_state=$(get_node_state "$layer")
  local ordinal=$(get_ordinal "$layer")
  local prev_ordinal=$(get_state "$layer" "ordinal")
  local prev_state=$(get_state "$layer" "node_state")
  local last_change=$(get_state "$layer" "last_change")
  local last_state_change=$(get_state "$layer" "last_state_change")
  local last_restart=$(get_state "$layer" "last_restart")
  
  # Initialize if first check
  if [[ -z "$prev_ordinal" ]]; then
    log "INIT: $layer state=$node_state ordinal=$ordinal"
    set_state "$layer" "ordinal" "$ordinal"
    set_state "$layer" "node_state" "$node_state"
    set_state "$layer" "last_change" "$now"
    set_state "$layer" "last_state_change" "$now"
    return 0
  fi
  
  # Check for state change
  if [[ "$node_state" != "$prev_state" ]]; then
    log "STATE: $layer changed $prev_state -> $node_state"
    set_state "$layer" "node_state" "$node_state"
    set_state "$layer" "last_state_change" "$now"
  fi
  
  # Check for stuck in bad state
  if echo "$node_state" | grep -qE "$STUCK_STATES"; then
    local stuck_time=$((now - last_state_change))
    if [[ "$stuck_time" -gt "$stuck_sec" ]]; then
      log "STUCK: $layer in $node_state for ${stuck_time}s"
      
      # Check cooldown
      if [[ -n "$last_restart" ]]; then
        local since_restart=$((now - last_restart))
        if [[ "$since_restart" -lt "$cooldown_sec" ]]; then
          log "COOLDOWN: $layer restarted ${since_restart}s ago, skipping"
          return 0
        fi
      fi
      
      # For GL0, check if it's the fresh-start deadlock
      if [[ "$layer" = "gl0" ]]; then
        if check_fresh_start_deadlock; then
          return 0  # Alert sent, don't restart blindly
        fi
      fi
      
      restart_layer "$layer" "stuck in $node_state"
      return $?
    fi
  fi
  
  # Ordinal unavailable
  if [[ "$ordinal" = "-1" ]]; then
    log "WARN: $layer ordinal unavailable (state=$node_state)"
    return 0
  fi
  
  # Ordinal changed - healthy
  if [[ "$ordinal" != "$prev_ordinal" ]]; then
    log "OK: $layer ordinal $prev_ordinal -> $ordinal (state=$node_state)"
    set_state "$layer" "ordinal" "$ordinal"
    set_state "$layer" "last_change" "$now"
    return 0
  fi
  
  # Ordinal unchanged - check stall (only for Ready state)
  if [[ "$node_state" = "Ready" ]]; then
    local stall_time=$((now - last_change))
    if [[ "$stall_time" -gt "$stall_sec" ]]; then
      log "STALL: $layer stuck at ordinal $ordinal for ${stall_time}s (state=Ready)"
      
      # Check cooldown
      if [[ -n "$last_restart" ]]; then
        local since_restart=$((now - last_restart))
        if [[ "$since_restart" -lt "$cooldown_sec" ]]; then
          log "COOLDOWN: $layer restarted ${since_restart}s ago, skipping"
          return 0
        fi
      fi
      
      restart_layer "$layer" "ordinal stall"
    else
      log "OK: $layer ordinal=$ordinal state=$node_state (unchanged ${stall_time}s)"
    fi
  else
    log "OK: $layer state=$node_state ordinal=$ordinal"
  fi
}

show_status() {
  echo "=== Layer Watchdog Status ==="
  echo ""
  
  for layer in gl0 ml0 cl1 dl1; do
    if ! is_container_running "$layer"; then
      echo "$layer: NOT RUNNING"
      continue
    fi
    
    local state=$(get_node_state "$layer")
    local ordinal=$(get_ordinal "$layer")
    local restarts=$(count_recent_restarts "$layer")
    local last_restart=$(get_state "$layer" "last_restart")
    
    local restart_info=""
    if [[ -n "$last_restart" ]]; then
      local ago=$(($(date +%s) - last_restart))
      restart_info=" (last restart: ${ago}s ago)"
    fi
    
    echo "$layer: state=$state ordinal=$ordinal restarts_1h=$restarts$restart_info"
  done
  
  echo ""
  
  # GL0 cluster status
  echo "=== GL0 Cluster ==="
  local cluster=$(get_cluster_info "gl0")
  echo "$cluster" | jq -r '.[] | "  \(.id[0:8]) \(.state)"' 2>/dev/null || echo "  (unavailable)"
}

check_all() {
  init_state
  
  # Check for deadlock first
  check_fresh_start_deadlock || true
  
  for layer in gl0 ml0 cl1 dl1; do
    check_layer "$layer"
  done
}

# Main
case "${1:-}" in
  --daemon)
    log "Starting watchdog daemon (interval: ${DAEMON_INTERVAL}s)"
    while true; do
      check_all
      sleep "$DAEMON_INTERVAL"
    done
    ;;
  --status)
    show_status
    ;;
  gl0|ml0|cl1|dl1)
    init_state
    check_layer "$1"
    ;;
  *)
    check_all
    ;;
esac
