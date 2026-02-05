#!/bin/bash
# Stop entire OttoChain cluster

echo "=== Stopping OttoChain Cluster ==="

# Stop in reverse order (DL1 → CL1 → ML0 → GL0)
echo "Stopping DL1..."
docker rm -f dl1-2 dl1-1 dl1 2>/dev/null || true

echo "Stopping CL1..."
docker rm -f cl1-2 cl1-1 cl1 2>/dev/null || true

echo "Stopping ML0..."
docker rm -f ml0-2 ml0-1 ml0 2>/dev/null || true

echo "Stopping GL0..."
docker rm -f gl0-2 gl0-1 gl0 2>/dev/null || true

echo ""
echo "All containers stopped."
docker ps --filter "name=gl0" --filter "name=ml0" --filter "name=cl1" --filter "name=dl1" --format "{{.Names}}"
