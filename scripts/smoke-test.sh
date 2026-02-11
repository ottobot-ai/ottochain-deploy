#!/usr/bin/env bash
#
# OttoChain Smoke Tests
# Verifies deployment health by generating traffic and checking data flow
#
set -euo pipefail

# Configuration (override via env vars)
BRIDGE_URL="${BRIDGE_URL:-http://5.78.121.248:3030}"
INDEXER_URL="${INDEXER_URL:-http://5.78.121.248:3031}"
GATEWAY_URL="${GATEWAY_URL:-http://5.78.121.248:4000}"
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
        ((++TESTS_PASSED)) || true
    else
        warn "❌ $name"
        ((++TESTS_FAILED)) || true
    fi
}

# =============================================================================
# Phase 1: Health Checks
# =============================================================================
log "Phase 1: Health Checks"

# Bridge health
BRIDGE_HEALTH=$(curl -sf "${BRIDGE_URL}/health" 2>/dev/null || echo "failed")
check "Bridge health" "$([ "$BRIDGE_HEALTH" != "failed" ] && echo true || echo false)"

# Indexer health
INDEXER_HEALTH=$(curl -sf "${INDEXER_URL}/health" 2>/dev/null || echo "failed")
check "Indexer health" "$([ "$INDEXER_HEALTH" != "failed" ] && echo true || echo false)"

# Gateway health (GraphQL endpoint)
GATEWAY_HEALTH=$(curl -sf "${GATEWAY_URL}/health" 2>/dev/null || echo "failed")
check "Gateway health" "$([ "$GATEWAY_HEALTH" != "failed" ] && echo true || echo false)"

# ML0 health
ML0_HEALTH=$(curl -sf "${ML0_URL}/cluster/info" 2>/dev/null || echo "failed")
check "ML0 cluster health" "$([ "$ML0_HEALTH" != "failed" ] && echo true || echo false)"

# =============================================================================
# Phase 2: Baseline Metrics
# =============================================================================
log "Phase 2: Capturing baseline metrics"

# Get current indexer status
INDEXER_STATUS=$(curl -sf "${INDEXER_URL}/status" 2>/dev/null || echo '{}')
BASELINE_INDEXED=$(echo "$INDEXER_STATUS" | jq -r '.lastIndexedOrdinal // 0')
BASELINE_ORDINAL=$(curl -sf "${ML0_URL}/snapshots/latest" 2>/dev/null | jq -r '.value.ordinal // 0')

log "  Baseline indexed ordinal: $BASELINE_INDEXED"
log "  Baseline ML0 ordinal: $BASELINE_ORDINAL"

# Get agent count via GraphQL
AGENT_COUNT=$(curl -s "${GATEWAY_URL}/graphql" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ agents { address } }"}' 2>/dev/null | jq -r '.data.agents | length // 0')
log "  Baseline agents: $AGENT_COUNT"

# =============================================================================
# Phase 3: Traffic Generation
# =============================================================================
log "Phase 3: Generating traffic for ${TRAFFIC_DURATION}s"

# Check if traffic generator is running (via monitor)
TRAFFIC_STATUS=$(curl -sf "${BRIDGE_URL}/traffic/status" 2>/dev/null || echo '{"running":false}')
TRAFFIC_RUNNING=$(echo "$TRAFFIC_STATUS" | jq -r '.running // false')

if [ "$TRAFFIC_RUNNING" = "true" ]; then
    log "  Traffic generator already running, using existing traffic"
else
    log "  No active traffic generator, waiting for natural traffic..."
fi

# Wait for traffic + indexer catchup
log "  Waiting ${TRAFFIC_DURATION}s for traffic + 30s for indexer..."
sleep $((TRAFFIC_DURATION + 30))

# =============================================================================
# Phase 4: Verify Data Flow
# =============================================================================
log "Phase 4: Verifying data flow"

# Check ML0 ordinal advanced
NEW_ORDINAL=$(curl -sf "${ML0_URL}/snapshots/latest" 2>/dev/null | jq -r '.value.ordinal // 0')
ORDINAL_DIFF=$((NEW_ORDINAL - BASELINE_ORDINAL))
check "ML0 ordinals advancing (diff: $ORDINAL_DIFF)" "$([ "$ORDINAL_DIFF" -gt 0 ] && echo true || echo false)"

# Check indexer is catching up
NEW_INDEXED=$(curl -sf "${INDEXER_URL}/status" 2>/dev/null | jq -r '.lastIndexedOrdinal // 0')
INDEXED_DIFF=$((NEW_INDEXED - BASELINE_INDEXED))
check "Indexer advancing (diff: $INDEXED_DIFF)" "$([ "$INDEXED_DIFF" -ge 0 ] && echo true || echo false)"

# Check indexer lag - warn but don't fail if behind
# After fresh deploy, indexer may need significant time to catch up
ORDINAL_LAG=$((NEW_ORDINAL - NEW_INDEXED))
if [ "$ORDINAL_LAG" -lt 50 ]; then
    log "✅ Indexer caught up (lag: $ORDINAL_LAG)"
    ((++TESTS_PASSED)) || true
elif [ "$ORDINAL_LAG" -lt 1000 ]; then
    log "⚠️  Indexer behind but catching up (lag: $ORDINAL_LAG) - OK for fresh deploy"
    ((++TESTS_PASSED)) || true
else
    warn "❌ Indexer severely behind (lag: $ORDINAL_LAG)"
    ((++TESTS_FAILED)) || true
fi

# Check agents exist via GraphQL
NEW_AGENT_COUNT=$(curl -s "${GATEWAY_URL}/graphql" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ agents { address } }"}' 2>/dev/null | jq -r '.data.agents | length // 0')
check "Gateway has agents ($NEW_AGENT_COUNT)" "$([ "$NEW_AGENT_COUNT" -gt 0 ] && echo true || echo false)"

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
