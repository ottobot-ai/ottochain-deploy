#!/bin/bash
# Check OttoChain cluster status

echo "========== OttoChain Cluster Status =========="
echo ""

echo "=== GL0 Layer ==="
echo -n "  Cluster size: "
curl -s http://localhost:9000/cluster/info 2>/dev/null | jq '. | length' || echo "N/A"
for p in 9000 9010 9020; do
  echo -n "  Port $p: "
  curl -s http://localhost:$p/node/info 2>/dev/null | jq -r .state || echo "DOWN"
done
echo ""

echo "=== ML0 Layer ==="
echo -n "  Cluster size: "
curl -s http://localhost:9200/cluster/info 2>/dev/null | jq '. | length' || echo "N/A"
for p in 9200 9210 9220; do
  echo -n "  Port $p: "
  curl -s http://localhost:$p/node/info 2>/dev/null | jq -r .state || echo "DOWN"
done
echo ""

echo "=== DL1 Layer ==="
echo -n "  Cluster size: "
curl -s http://localhost:9400/cluster/info 2>/dev/null | jq '. | length' || echo "N/A"
for p in 9400 9410 9420; do
  echo -n "  Port $p: "
  curl -s http://localhost:$p/node/info 2>/dev/null | jq -r .state || echo "DOWN"
done
echo ""

echo "=== Containers ==="
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "NAMES|gl0|ml0|dl1" | sort
