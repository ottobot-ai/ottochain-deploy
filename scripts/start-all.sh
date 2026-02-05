#!/bin/bash
# Start entire OttoChain cluster (GL0 → ML0 → CL1 → DL1)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo "     OttoChain Full Metagraph Startup      "
echo "============================================"
echo ""

# Create network if needed
docker network create ottochain_ottochain 2>/dev/null || true

# Start layers in order
echo "Step 1/4: Starting GL0..."
$SCRIPT_DIR/start-gl0.sh
echo ""

echo "Step 2/4: Starting ML0..."
$SCRIPT_DIR/start-ml0.sh
echo ""

echo "Step 3/4: Starting CL1 (Currency Layer)..."
$SCRIPT_DIR/start-cl1.sh
echo ""

echo "Step 3.5: Bootstrapping CL1 currency (sending initial transaction)..."
$SCRIPT_DIR/bootstrap-currency.sh || echo "Warning: Bootstrap failed, CL1 may not produce blocks until a transaction is sent"
echo ""

echo "Step 4/4: Starting DL1 (Data Layer)..."
$SCRIPT_DIR/start-dl1.sh
echo ""

echo "============================================"
echo "             Cluster Summary               "
echo "============================================"
$SCRIPT_DIR/status.sh
