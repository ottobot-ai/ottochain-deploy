#!/bin/bash
# layer-watchdog.sh - Monitor all layers, restart on stall
#
# Checks ordinal progression (not just HTTP response).
# Queries local containers or optional monitor API.
#
# Usage:
#   ./layer-watchdog.sh              # Single check all layers
#   ./layer-watchdog.sh ml0          # Single check specific layer
#   ./layer-watchdog.sh --daemon     # Continuous monitoring
#
# Cron (recommended):
#   */2 * * * * /opt/ottochain/scripts/layer-watchdog.sh >> /var/log/layer-watchdog.log 2>&1

set -euo pipefail

STATE_FILE="/tmp/layer-watchdog-state.json"
STALL_THRESHOLD_MINUTES="${STALL_THRESHOLD_MINUTES:-4}"
COOLDOWN_MINUTES="${COOLDOWN_MINUTES:-10}"
DAEMON_INTERVAL="${DAEMON_INTERVAL:-120}"

# Layer config: name -> port, ordinal endpoint
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
  
  # Handle both {value: {ordinal: N}} and {ordinal: N} formats
  local ordinal
  ordinal=$(echo "$result" | jq -r '.value.ordinal // .ordinal // -1' 2>/dev/null) || ordinal=-1
  echo "$ordinal"
}

is_container_running() {
  docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${1}$"
}

restart_layer() {
  local layer=$1
  log "RESTART: Restarting $layer..."
  
  if docker restart "$layer" 2>/dev/null; then
    log "RESTART: $layer restarted successfully"
    set_state "$layer" "last_restart" "$(date +%s)"
    return 0
  else
    log "ERROR: Failed to restart $layer"
    return 1
  fi
}

check_layer() {
  local layer=$1
  local now=$(date +%s)
  local threshold_sec=$((STALL_THRESHOLD_MINUTES * 60))
  local cooldown_sec=$((COOLDOWN_MINUTES * 60))
  
  # Skip if container not running
  if ! is_container_running "$layer"; then
    log "SKIP: $layer container not running"
    return 0
  fi
  
  local ordinal=$(get_ordinal "$layer")
  local prev_ordinal=$(get_state "$layer" "ordinal")
  local last_change=$(get_state "$layer" "last_change")
  local last_restart=$(get_state "$layer" "last_restart")
  
  # Initialize if first check
  if [[ -z "$prev_ordinal" ]]; then
    log "INIT: $layer ordinal=$ordinal"
    set_state "$layer" "ordinal" "$ordinal"
    set_state "$layer" "last_change" "$now"
    return 0
  fi
  
  # Ordinal unavailable
  if [[ "$ordinal" == "-1" ]]; then
    log "WARN: $layer ordinal unavailable (endpoint down?)"
    return 0
  fi
  
  # Ordinal changed - healthy
  if [[ "$ordinal" != "$prev_ordinal" ]]; then
    log "OK: $layer ordinal $prev_ordinal -> $ordinal"
    set_state "$layer" "ordinal" "$ordinal"
    set_state "$layer" "last_change" "$now"
    return 0
  fi
  
  # Ordinal unchanged - check stall
  local stall_time=$((now - last_change))
  if [[ "$stall_time" -gt "$threshold_sec" ]]; then
    log "STALL: $layer stuck at ordinal $ordinal for ${stall_time}s"
    
    # Check cooldown
    if [[ -n "$last_restart" ]]; then
      local since_restart=$((now - last_restart))
      if [[ "$since_restart" -lt "$cooldown_sec" ]]; then
        log "COOLDOWN: $layer restarted ${since_restart}s ago, skipping"
        return 0
      fi
    fi
    
    restart_layer "$layer"
  else
    log "OK: $layer ordinal=$ordinal (unchanged ${stall_time}s)"
  fi
}

check_all() {
  init_state
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
  gl0|ml0|cl1|dl1)
    init_state
    check_layer "$1"
    ;;
  *)
    check_all
    ;;
esac
