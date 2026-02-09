#!/bin/bash
# check-versions.sh - Aggregate version info from all OttoChain services
# Usage: ./scripts/check-versions.sh [SERVICES_HOST] [METAGRAPH_HOST]
#
# Environment variables:
#   SERVICES_HOST - IP/hostname of services server (default: localhost)
#   METAGRAPH_HOST - IP/hostname of metagraph node (default: localhost)

set -e

SERVICES_HOST="${1:-${SERVICES_HOST:-localhost}}"
METAGRAPH_HOST="${2:-${METAGRAPH_HOST:-localhost}}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "════════════════════════════════════════════════════════════════"
echo "                 OttoChain Version Report"
echo "════════════════════════════════════════════════════════════════"
echo ""

fetch_version() {
    local name=$1
    local url=$2
    local result
    
    if result=$(curl -sf --max-time 3 "$url" 2>/dev/null); then
        local version=$(echo "$result" | jq -r '.version // "?"')
        local commit=$(echo "$result" | jq -r '.commit // .GIT_SHA // "-"' | head -c 7)
        local built=$(echo "$result" | jq -r '.built // .BUILD_TIME // "-"')
        echo -e "${GREEN}✓${NC} ${CYAN}$name${NC}: v$version (${commit})"
    else
        echo -e "${RED}✗${NC} ${CYAN}$name${NC}: unreachable"
    fi
}

fetch_node_info() {
    local name=$1
    local url=$2
    local result
    
    if result=$(curl -sf --max-time 3 "$url/node/info" 2>/dev/null); then
        local version=$(echo "$result" | jq -r '.version // "?"')
        local state=$(echo "$result" | jq -r '.state // "?"')
        local id=$(echo "$result" | jq -r '.id // "-"' | head -c 8)
        echo -e "${GREEN}✓${NC} ${CYAN}$name${NC}: $version ($state) [${id}...]"
    else
        echo -e "${RED}✗${NC} ${CYAN}$name${NC}: unreachable"
    fi
}

echo "📦 Services (${SERVICES_HOST})"
echo "────────────────────────────────────────────────────────────────"
fetch_version "bridge"   "http://${SERVICES_HOST}:3030/version"
fetch_version "indexer"  "http://${SERVICES_HOST}:3031/version"
fetch_version "gateway"  "http://${SERVICES_HOST}:4000/version"
fetch_version "monitor"  "http://${SERVICES_HOST}:3032/version"

echo ""
echo "🔷 Metagraph Nodes (${METAGRAPH_HOST})"
echo "────────────────────────────────────────────────────────────────"
fetch_node_info "GL0"    "http://${METAGRAPH_HOST}:9000"
fetch_node_info "ML0"    "http://${METAGRAPH_HOST}:9200"
fetch_node_info "CL1"    "http://${METAGRAPH_HOST}:9300"
fetch_node_info "DL1-0"  "http://${METAGRAPH_HOST}:9400"
fetch_node_info "DL1-1"  "http://${METAGRAPH_HOST}:9410"
fetch_node_info "DL1-2"  "http://${METAGRAPH_HOST}:9420"

echo ""

# If monitor is available, get aggregated view
echo "📊 Monitor Aggregation"
echo "────────────────────────────────────────────────────────────────"
if result=$(curl -sf --max-time 3 "http://${SERVICES_HOST}:3032/api/versions" 2>/dev/null); then
    echo "$result" | jq -C .
else
    echo -e "${YELLOW}⚠${NC}  Monitor /api/versions endpoint not available"
    echo "   Run 'curl http://${SERVICES_HOST}:3032/api/status' for basic status"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
