#!/bin/bash
# OttoChain Auto-Heal Script
# Detects stuck layers and performs rolling restarts
# Usage: ./heal-cluster.sh [--dry-run] [--watch INTERVAL]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/.env" 2>/dev/null || true

# Config
NODE1="${NODE1_IP:-5.78.90.207}"
STALL_THRESHOLD_MINUTES=${STALL_THRESHOLD_MINUTES:-4}
STATE_FILE="/tmp/ottochain-heal-state.json"
WEBHOOK_URL="${OTTOCHAIN_ALERT_WEBHOOK:-}"

DRY_RUN=false
WATCH_MODE=false
WATCH_INTERVAL=120

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --watch) WATCH_MODE=true; WATCH_INTERVAL=${2:-120}; shift 2 ;;
        *) shift ;;
    esac
done

# Initialize state
if [ ! -f "$STATE_FILE" ]; then
    cat > "$STATE_FILE" << 'EOF'
{
    "gl0": {"ordinal": -1, "lastChange": 0},
    "ml0": {"ordinal": -1, "lastChange": 0},
    "dl1": {"ordinal": -1, "lastChange": 0},
    "lastHeal": {}
}
EOF
fi

get_ordinal() {
    local port=$1
    local endpoint=${2:-"/snapshots/latest"}
    
    result=$(curl -s --connect-timeout 5 "http://$NODE1:$port$endpoint" 2>/dev/null)
    ordinal=$(echo "$result" | jq -r '.value.ordinal // .ordinal // -1' 2>/dev/null)
    echo "${ordinal:--1}"
}

send_alert() {
    local message=$1
    echo "[HEAL] $message"
    
    if [ -n "$WEBHOOK_URL" ]; then
        curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"🔧 **OttoChain Auto-Heal**\n\n$message\"}" \
            >/dev/null 2>&1 || true
    fi
}

do_restart() {
    local layer=$1
    
    if $DRY_RUN; then
        echo "[DRY-RUN] Would restart $layer"
        return 0
    fi
    
    send_alert "Restarting $layer due to stalled ordinals"
    "$SCRIPT_DIR/restart-layer.sh" "$layer" --force
}

check_and_heal() {
    local now=$(date +%s)
    local state=$(cat "$STATE_FILE")
    local threshold_sec=$((STALL_THRESHOLD_MINUTES * 60))
    
    # Get current ordinals
    local gl0_ord=$(get_ordinal 9000 "/global-snapshots/latest")
    local ml0_ord=$(get_ordinal 9200 "/snapshots/latest")
    local dl1_ord=$(get_ordinal 9400 "/data/latest")
    
    echo "Current ordinals: GL0=$gl0_ord ML0=$ml0_ord DL1=$dl1_ord"
    
    # Check each layer
    for layer in gl0 ml0 dl1; do
        local ord_var="${layer}_ord"
        local current_ord=${!ord_var}
        
        local prev_ord=$(echo "$state" | jq -r ".$layer.ordinal // -1")
        local last_change=$(echo "$state" | jq -r ".$layer.lastChange // 0")
        local last_heal=$(echo "$state" | jq -r ".lastHeal.$layer // 0")
        
        # Skip if ordinal is -1 (endpoint not available)
        if [ "$current_ord" -eq -1 ]; then
            continue
        fi
        
        # Update state if ordinal changed
        if [ "$current_ord" -ne "$prev_ord" ]; then
            state=$(echo "$state" | jq ".$layer.ordinal = $current_ord | .$layer.lastChange = $now")
            echo "$layer: ordinal changed $prev_ord -> $current_ord"
        else
            # Check if stalled
            local stall_time=$((now - last_change))
            if [ "$last_change" -gt 0 ] && [ "$stall_time" -gt "$threshold_sec" ]; then
                # Check cooldown (don't restart same layer within 10 min)
                local cooldown=$((now - last_heal))
                if [ "$cooldown" -gt 600 ]; then
                    echo "$layer: STALLED for ${stall_time}s (threshold: ${threshold_sec}s)"
                    do_restart "$layer"
                    state=$(echo "$state" | jq ".lastHeal.$layer = $now")
                else
                    echo "$layer: stalled but in cooldown (${cooldown}s since last heal)"
                fi
            fi
        fi
    done
    
    # Save state
    echo "$state" > "$STATE_FILE"
}

main() {
    echo "=== OttoChain Auto-Heal ==="
    echo "Time: $(date)"
    echo "Stall threshold: ${STALL_THRESHOLD_MINUTES} minutes"
    echo "Dry run: $DRY_RUN"
    echo ""
    
    check_and_heal
}

if $WATCH_MODE; then
    echo "Starting heal watcher (interval: ${WATCH_INTERVAL}s)..."
    while true; do
        main
        echo ""
        echo "Next check in ${WATCH_INTERVAL}s..."
        sleep "$WATCH_INTERVAL"
    done
else
    main
fi
