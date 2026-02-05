#!/bin/bash
# Start entire OttoChain cluster (GL0 → ML0 → DL1)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo "       OttoChain 3×3 Cluster Startup       "
echo "============================================"
echo ""

# Create network if needed
docker network create ottochain_ottochain 2>/dev/null || true

# Start layers in order
echo "Step 1/3: Starting GL0..."
$SCRIPT_DIR/start-gl0.sh
echo ""

echo "Step 2/3: Starting ML0..."
$SCRIPT_DIR/start-ml0.sh
echo ""

echo "Step 3/3: Starting DL1..."
$SCRIPT_DIR/start-dl1.sh
echo ""

echo "============================================"
echo "             Cluster Summary               "
echo "============================================"
$SCRIPT_DIR/status.sh
