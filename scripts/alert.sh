#!/bin/bash
# OttoChain Alert Script
# Checks node health and sends alerts via webhook
# Can be run via cron, systemd timer, or as a watcher daemon

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="/tmp/ottochain-alert-state.json"
ALERT_COOLDOWN=300  # 5 minutes between repeat alerts

# Load config if exists
if [ -f "$SCRIPT_DIR/.env.alert" ]; then
    source "$SCRIPT_DIR/.env.alert"
fi

# Webhook URL for OttoAlert (set in .env.alert or environment)
WEBHOOK_URL="${OTTOCHAIN_ALERT_WEBHOOK:-}"

# Nodes to monitor (port:name)
NODES=(
    "9000:GL0-0"
    "9010:GL0-1"
    "9020:GL0-2"
    "9200:ML0-0"
    "9210:ML0-1"
    "9220:ML0-2"
    "9400:DL1-0"
    "9410:DL1-1"
    "9420:DL1-2"
)

# Initialize state file if missing
if [ ! -f "$STATE_FILE" ]; then
    echo '{"lastAlert":0,"unhealthy":[]}' > "$STATE_FILE"
fi

check_node() {
    local port=$1
    local name=$2
    local result
    
    result=$(curl -s --connect-timeout 5 "http://localhost:$port/node/info" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$result" ]; then
        echo "DOWN"
        return
    fi
    
    local state=$(echo "$result" | jq -r '.state // "UNKNOWN"')
    local session=$(echo "$result" | jq -r '.session // "0"')
    
    echo "$state:$session"
}

send_alert() {
    local message=$1
    local severity=${2:-"warning"}
    
    echo "[ALERT] $message"
    
    if [ -n "$WEBHOOK_URL" ]; then
        curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"🚨 **OttoChain Alert**\n\n$message\", \"severity\": \"$severity\"}" \
            >/dev/null 2>&1 || true
    fi
}

main() {
    local now=$(date +%s)
    local prev_state=$(cat "$STATE_FILE")
    local prev_unhealthy=$(echo "$prev_state" | jq -r '.unhealthy | join(",")')
    local last_alert=$(echo "$prev_state" | jq -r '.lastAlert')
    
    local current_unhealthy=()
    local new_failures=()
    local recoveries=()
    local restarts=()
    
    for node_def in "${NODES[@]}"; do
        IFS=':' read -r port name <<< "$node_def"
        result=$(check_node "$port" "$name")
        
        state="${result%%:*}"
        session="${result#*:}"
        
        if [ "$state" = "DOWN" ] || [ "$state" = "UNKNOWN" ]; then
            current_unhealthy+=("$name")
            if [[ ! ",$prev_unhealthy," =~ ",$name," ]]; then
                new_failures+=("$name")
            fi
        elif [ "$state" = "Ready" ]; then
            # Check for restart (session change)
            prev_session=$(echo "$prev_state" | jq -r ".sessions.\"$name\" // \"0\"")
            if [ "$prev_session" != "0" ] && [ "$prev_session" != "$session" ]; then
                restarts+=("$name")
            fi
            
            # Check for recovery
            if [[ ",$prev_unhealthy," =~ ",$name," ]]; then
                recoveries+=("$name")
            fi
        fi
    done
    
    # Build new state
    local new_state=$(jq -n \
        --argjson unhealthy "$(printf '%s\n' "${current_unhealthy[@]}" | jq -R . | jq -s .)" \
        --argjson lastAlert "$last_alert" \
        '{unhealthy: $unhealthy, lastAlert: $lastAlert, sessions: {}}')
    
    # Alert on new failures
    if [ ${#new_failures[@]} -gt 0 ]; then
        send_alert "Node(s) went DOWN: ${new_failures[*]}" "critical"
        new_state=$(echo "$new_state" | jq ".lastAlert = $now")
    fi
    
    # Alert on recoveries
    if [ ${#recoveries[@]} -gt 0 ]; then
        send_alert "Node(s) RECOVERED: ${recoveries[*]}" "info"
    fi
    
    # Alert on restarts
    if [ ${#restarts[@]} -gt 0 ]; then
        send_alert "Node(s) RESTARTED: ${restarts[*]}" "info"
    fi
    
    # Save state
    echo "$new_state" > "$STATE_FILE"
    
    # Summary output
    if [ ${#current_unhealthy[@]} -eq 0 ]; then
        echo "[OK] All nodes healthy"
    else
        echo "[WARN] Unhealthy: ${current_unhealthy[*]}"
    fi
}

# Run modes
case "${1:-check}" in
    check)
        main
        ;;
    watch)
        echo "Starting alert watcher (interval: ${2:-60}s)..."
        while true; do
            main
            sleep "${2:-60}"
        done
        ;;
    *)
        echo "Usage: $0 [check|watch [interval]]"
        exit 1
        ;;
esac
