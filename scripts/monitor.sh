#!/bin/bash
# OttoChain Cluster Monitor
# Checks ordinal progression, not just Ready state
# Usage: ./monitor.sh [--json] [--watch INTERVAL]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/.env" 2>/dev/null || true

# Node IPs (override via .env or environment)
NODE1="${NODE1_IP:-5.78.90.207}"
NODE2="${NODE2_IP:-5.78.113.25}"
NODE3="${NODE3_IP:-5.78.107.77}"
SERVICES="${SERVICES_IP:-5.78.121.248}"

# Ports
GL0_PORT=9000
ML0_PORT=9200
CL1_PORT=9300
DL1_PORT=9400

# State file for tracking ordinal history
STATE_FILE="/tmp/ottochain-monitor-state.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

get_ordinal() {
    local host=$1
    local port=$2
    local endpoint=${3:-"/snapshots/latest"}
    
    result=$(curl -s --connect-timeout 5 "http://$host:$port$endpoint" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$result" ]; then
        echo "-1"
        return
    fi
    
    ordinal=$(echo "$result" | jq -r '.value.ordinal // .ordinal // -1' 2>/dev/null)
    echo "${ordinal:--1}"
}

get_cluster_state() {
    local host=$1
    local port=$2
    
    result=$(curl -s --connect-timeout 5 "http://$host:$port/cluster/info" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$result" ]; then
        echo "DOWN:0"
        return
    fi
    
    state=$(echo "$result" | jq -r '.[0].state // "UNKNOWN"')
    count=$(echo "$result" | jq -r 'length')
    echo "$state:$count"
}

check_status_api() {
    result=$(curl -s --connect-timeout 5 "http://$SERVICES:3032/api/status" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$result" ]; then
        echo '{"overall":"unavailable"}'
        return
    fi
    echo "$result"
}

main() {
    local json_output=false
    local watch_mode=false
    local watch_interval=60
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --json) json_output=true; shift ;;
            --watch) watch_mode=true; watch_interval=${2:-60}; shift 2 ;;
            *) shift ;;
        esac
    done
    
    # Load previous state
    if [ -f "$STATE_FILE" ]; then
        prev_state=$(cat "$STATE_FILE")
    else
        prev_state='{}'
    fi
    
    # Collect current state
    local now=$(date +%s)
    local gl0_ordinal=$(get_ordinal "$NODE1" "$GL0_PORT" "/global-snapshots/latest")
    local ml0_ordinal=$(get_ordinal "$NODE1" "$ML0_PORT" "/snapshots/latest")
    local dl1_ordinal=$(get_ordinal "$NODE1" "$DL1_PORT" "/data/latest")
    
    local gl0_state=$(get_cluster_state "$NODE1" "$GL0_PORT")
    local ml0_state=$(get_cluster_state "$NODE1" "$ML0_PORT")
    local cl1_state=$(get_cluster_state "$NODE1" "$CL1_PORT")
    local dl1_state=$(get_cluster_state "$NODE1" "$DL1_PORT")
    
    # Check ordinal progression
    local prev_gl0=$(echo "$prev_state" | jq -r '.gl0_ordinal // -1')
    local prev_ml0=$(echo "$prev_state" | jq -r '.ml0_ordinal // -1')
    local prev_dl1=$(echo "$prev_state" | jq -r '.dl1_ordinal // -1')
    local prev_time=$(echo "$prev_state" | jq -r '.timestamp // 0')
    
    local gl0_progressing=true
    local ml0_progressing=true
    local dl1_progressing=true
    
    # Only check progression if we have previous data and >2 min elapsed
    if [ "$prev_time" -gt 0 ] && [ $((now - prev_time)) -gt 120 ]; then
        [ "$gl0_ordinal" -le "$prev_gl0" ] && [ "$gl0_ordinal" -gt 0 ] && gl0_progressing=false
        [ "$ml0_ordinal" -le "$prev_ml0" ] && [ "$ml0_ordinal" -gt 0 ] && ml0_progressing=false
        [ "$dl1_ordinal" -le "$prev_dl1" ] && [ "$dl1_ordinal" -gt 0 ] && dl1_progressing=false
    fi
    
    # Save current state
    cat > "$STATE_FILE" << EOF
{
    "timestamp": $now,
    "gl0_ordinal": $gl0_ordinal,
    "ml0_ordinal": $ml0_ordinal,
    "dl1_ordinal": $dl1_ordinal
}
EOF
    
    if $json_output; then
        cat << EOF
{
    "timestamp": $now,
    "layers": {
        "gl0": {"state": "${gl0_state%%:*}", "nodes": ${gl0_state##*:}, "ordinal": $gl0_ordinal, "progressing": $gl0_progressing},
        "ml0": {"state": "${ml0_state%%:*}", "nodes": ${ml0_state##*:}, "ordinal": $ml0_ordinal, "progressing": $ml0_progressing},
        "cl1": {"state": "${cl1_state%%:*}", "nodes": ${cl1_state##*:}},
        "dl1": {"state": "${dl1_state%%:*}", "nodes": ${dl1_state##*:}, "ordinal": $dl1_ordinal, "progressing": $dl1_progressing}
    },
    "healthy": $([ "${gl0_state%%:*}" = "Ready" ] && [ "${ml0_state%%:*}" = "Ready" ] && [ "${dl1_state%%:*}" = "Ready" ] && $gl0_progressing && $ml0_progressing && echo true || echo false)
}
EOF
    else
        echo "=== OttoChain Cluster Status ==="
        echo "Time: $(date -d @$now)"
        echo ""
        
        # GL0
        printf "GL0: "
        if [ "${gl0_state%%:*}" = "Ready" ]; then
            printf "${GREEN}Ready${NC} (${gl0_state##*:} nodes)"
        else
            printf "${RED}${gl0_state%%:*}${NC}"
        fi
        if [ "$gl0_ordinal" -gt 0 ]; then
            printf " ordinal=$gl0_ordinal"
            if ! $gl0_progressing; then
                printf " ${RED}STUCK${NC}"
            fi
        fi
        echo ""
        
        # ML0
        printf "ML0: "
        if [ "${ml0_state%%:*}" = "Ready" ]; then
            printf "${GREEN}Ready${NC} (${ml0_state##*:} nodes)"
        else
            printf "${RED}${ml0_state%%:*}${NC}"
        fi
        if [ "$ml0_ordinal" -gt 0 ]; then
            printf " ordinal=$ml0_ordinal"
            if ! $ml0_progressing; then
                printf " ${RED}STUCK${NC}"
            fi
        fi
        echo ""
        
        # CL1
        printf "CL1: "
        if [ "${cl1_state%%:*}" = "Ready" ]; then
            printf "${GREEN}Ready${NC} (${cl1_state##*:} nodes)"
        else
            printf "${RED}${cl1_state%%:*}${NC}"
        fi
        echo ""
        
        # DL1
        printf "DL1: "
        if [ "${dl1_state%%:*}" = "Ready" ]; then
            printf "${GREEN}Ready${NC} (${dl1_state##*:} nodes)"
        else
            printf "${RED}${dl1_state%%:*}${NC}"
        fi
        if [ "$dl1_ordinal" -gt 0 ]; then
            printf " ordinal=$dl1_ordinal"
            if ! $dl1_progressing; then
                printf " ${RED}STUCK${NC}"
            fi
        elif [ "$dl1_ordinal" -eq -1 ]; then
            printf " ${YELLOW}no snapshots${NC}"
        fi
        echo ""
        
        # Summary
        echo ""
        if [ "${gl0_state%%:*}" = "Ready" ] && [ "${ml0_state%%:*}" = "Ready" ] && [ "${dl1_state%%:*}" = "Ready" ] && $gl0_progressing && $ml0_progressing; then
            echo -e "${GREEN}✓ Cluster healthy${NC}"
        else
            echo -e "${RED}✗ Cluster unhealthy${NC}"
        fi
    fi
}

if [[ "${1:-}" == "--watch" ]]; then
    interval=${2:-60}
    echo "Watching cluster (interval: ${interval}s)..."
    while true; do
        clear
        main
        sleep "$interval"
    done
else
    main "$@"
fi
