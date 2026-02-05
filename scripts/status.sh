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

echo "=== CL1 Layer ==="
echo -n "  Cluster size: "
curl -s http://localhost:9300/cluster/info 2>/dev/null | jq '. | length' || echo "N/A"
for p in 9300 9310 9320; do
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

echo "=== IDs ==="
echo -n "  GL0_PEER_ID: "
cat /opt/ottochain/gl0-peer-id 2>/dev/null | head -c 30 && echo "..." || echo "N/A"
echo -n "  ML0_PEER_ID: "
cat /opt/ottochain/ml0-peer-id 2>/dev/null | head -c 30 && echo "..." || echo "N/A"
echo -n "  TOKEN_ID: "
cat /opt/ottochain/token-id 2>/dev/null | head -c 30 && echo "..." || echo "N/A"
echo ""

echo "=== Containers ==="
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "NAMES|gl0|ml0|cl1|dl1" | sort
