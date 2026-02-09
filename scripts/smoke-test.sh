#!/usr/bin/env bash
#
# OttoChain Smoke Tests
# Verifies deployment health by generating traffic and checking explorer
#
set -euo pipefail

# Configuration (override via env vars)
SERVICES_URL="${SERVICES_URL:-http://5.78.121.248:3030}"
EXPLORER_URL="${EXPLORER_URL:-http://5.78.121.248:8080}"
ML0_URL="${ML0_URL:-http://5.78.90.207:9200}"
TRAFFIC_DURATION="${TRAFFIC_DURATION:-60}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[SMOKE]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# Track test results
TESTS_PASSED=0
TESTS_FAILED=0

check() {
    local name="$1"
    local result="$2"
    if [ "$result" = "true" ] || [ "$result" = "0" ]; then
        log "✅ $name"
        ((TESTS_PASSED++))
    else
        warn "❌ $name"
        ((TESTS_FAILED++))
    fi
}

# =============================================================================
# Phase 1: Health Checks
# =============================================================================
log "Phase 1: Health Checks"

# Bridge health
BRIDGE_HEALTH=$(curl -sf "${SERVICES_URL}/health" 2>/dev/null || echo "failed")
check "Bridge health" "$([ "$BRIDGE_HEALTH" != "failed" ] && echo true || echo false)"

# Explorer health  
EXPLORER_HEALTH=$(curl -sf "${EXPLORER_URL}/api/health" 2>/dev/null || echo "failed")
check "Explorer API health" "$([ "$EXPLORER_HEALTH" != "failed" ] && echo true || echo false)"

# ML0 health
ML0_HEALTH=$(curl -sf "${ML0_URL}/cluster/info" 2>/dev/null || echo "failed")
check "ML0 cluster health" "$([ "$ML0_HEALTH" != "failed" ] && echo true || echo false)"

# =============================================================================
# Phase 2: Baseline Metrics
# =============================================================================
log "Phase 2: Capturing baseline metrics"

# Get current explorer counts
BASELINE_AGENTS=$(curl -sf "${EXPLORER_URL}/api/agents?limit=1" 2>/dev/null | jq -r '.total // 0')
BASELINE_ORDINAL=$(curl -sf "${ML0_URL}/global-snapshots/latest" 2>/dev/null | jq -r '.value.ordinal // 0')

log "  Baseline agents: $BASELINE_AGENTS"
log "  Baseline ML0 ordinal: $BASELINE_ORDINAL"

# =============================================================================
# Phase 3: Traffic Generation
# =============================================================================
log "Phase 3: Generating traffic for ${TRAFFIC_DURATION}s"

# Check if traffic generator is running on services node
TRAFFIC_STATUS=$(curl -sf "${SERVICES_URL}/traffic/status" 2>/dev/null || echo '{"running":false}')
TRAFFIC_RUNNING=$(echo "$TRAFFIC_STATUS" | jq -r '.running // false')

if [ "$TRAFFIC_RUNNING" = "true" ]; then
    log "  Traffic generator already running, using existing traffic"
else
    log "  Starting traffic generator burst..."
    curl -sf -X POST "${SERVICES_URL}/traffic/start?duration=${TRAFFIC_DURATION}" 2>/dev/null || warn "Could not start traffic generator"
fi

# Wait for traffic + indexer catchup
log "  Waiting ${TRAFFIC_DURATION}s for traffic + 30s for indexer..."
sleep $((TRAFFIC_DURATION + 30))

# =============================================================================
# Phase 4: Verify Data Flow
# =============================================================================
log "Phase 4: Verifying data flow"

# Check ML0 ordinal advanced
NEW_ORDINAL=$(curl -sf "${ML0_URL}/global-snapshots/latest" 2>/dev/null | jq -r '.value.ordinal // 0')
ORDINAL_DIFF=$((NEW_ORDINAL - BASELINE_ORDINAL))
check "ML0 ordinals advancing (diff: $ORDINAL_DIFF)" "$([ "$ORDINAL_DIFF" -gt 0 ] && echo true || echo false)"

# Check explorer has agents
NEW_AGENTS=$(curl -sf "${EXPLORER_URL}/api/agents?limit=1" 2>/dev/null | jq -r '.total // 0')
check "Explorer has agents ($NEW_AGENTS)" "$([ "$NEW_AGENTS" -gt 0 ] && echo true || echo false)"

# Check explorer has recent transactions
RECENT_TXS=$(curl -sf "${EXPLORER_URL}/api/transactions?limit=5" 2>/dev/null | jq -r '.data | length // 0')
check "Explorer has recent transactions ($RECENT_TXS)" "$([ "$RECENT_TXS" -gt 0 ] && echo true || echo false)"

# Check indexer is caught up (within 5 ordinals of ML0)
INDEXED_ORDINAL=$(curl -sf "${EXPLORER_URL}/api/status" 2>/dev/null | jq -r '.lastIndexedOrdinal // 0')
ORDINAL_LAG=$((NEW_ORDINAL - INDEXED_ORDINAL))
check "Indexer caught up (lag: $ORDINAL_LAG)" "$([ "$ORDINAL_LAG" -lt 10 ] && echo true || echo false)"

# =============================================================================
# Results
# =============================================================================
echo ""
log "========================================="
log "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
log "========================================="

if [ "$TESTS_FAILED" -gt 0 ]; then
    fail "Smoke tests failed!"
else
    log "🎉 All smoke tests passed!"
    exit 0
fi
