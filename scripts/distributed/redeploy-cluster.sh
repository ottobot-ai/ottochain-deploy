#!/bin/bash
# Full teardown and redeploy of OttoChain cluster
# Usage: ./scripts/distributed/redeploy-cluster.sh [--skip-jars]
#
# This script:
# 1. Stops all nodes
# 2. Cleans all data
# 3. Optionally redeploys JARs
# 4. Starts fresh cluster with new genesis

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../inventory.sh"

SKIP_JARS=false
if [ "$1" == "--skip-jars" ]; then
    SKIP_JARS=true
fi

echo "============================================"
echo "     OttoChain Full Cluster Redeploy"
echo "============================================"
echo ""
echo "This will:"
echo "  1. Stop all nodes on all machines"
echo "  2. Clean all data (fresh genesis)"
echo "  3. Redeploy JARs (unless --skip-jars)"
echo "  4. Start new cluster"
echo ""
echo "Nodes: ${NODES[*]}"
echo ""

read -p "Are you sure? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "=== Step 1: Stopping cluster ==="
"$SCRIPT_DIR/stop-cluster.sh" --clean

if [ "$SKIP_JARS" = false ]; then
    echo ""
    echo "=== Step 2: Deploying JARs ==="
    "$SCRIPT_DIR/deploy-jars.sh" --from-node1
else
    echo ""
    echo "=== Step 2: Skipping JAR deployment ==="
fi

echo ""
echo "=== Step 3: Starting cluster ==="
"$SCRIPT_DIR/start-cluster.sh" --genesis

echo ""
echo "=== Step 4: Verifying ==="
sleep 10
"$SCRIPT_DIR/status-cluster.sh"

echo ""
echo "============================================"
echo "     Redeploy Complete"
echo "============================================"
