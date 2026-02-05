#!/bin/bash
# Start DL1 cluster (3 nodes)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"

# Reload peer IDs
GL0_PEER_ID=$(cat /opt/ottochain/gl0-peer-id)
ML0_PEER_ID=$(cat /opt/ottochain/ml0-peer-id)
TOKEN_ID=$(cat /opt/ottochain/token-id)

echo "=== Starting DL1 Cluster ==="
echo "TOKEN_ID: $TOKEN_ID"

# Stop existing
docker rm -f dl1 dl1-1 dl1-2 2>/dev/null || true

# DL1 Primary (initial-validator)
echo "Starting DL1 primary as initial-validator..."
docker run -d --name dl1 \
  --network $NETWORK \
  -p 9400:9400 -p 9401:9401 -p 9402:9402 \
  -v $JARS_DIR:/jars:ro \
  -v $KEYS_DIR:/keys:ro \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9400 \
  -e CL_P2P_HTTP_PORT=9401 \
  -e CL_CLI_HTTP_PORT=9402 \
  -e CL_EXTERNAL_IP=$HOST_IP \
  -e CL_APP_ENV=$CL_APP_ENV \
  -e CL_GLOBAL_L0_PEER_HTTP_HOST=$HOST_IP \
  -e CL_GLOBAL_L0_PEER_HTTP_PORT=9000 \
  -e CL_GLOBAL_L0_PEER_ID=$GL0_PEER_ID \
  -e CL_L0_PEER_HTTP_HOST=$HOST_IP \
  -e CL_L0_PEER_HTTP_PORT=9200 \
  -e CL_L0_PEER_ID=$ML0_PEER_ID \
  -e CL_L0_TOKEN_IDENTIFIER=$TOKEN_ID \
  -e CL_COLLATERAL=$CL_COLLATERAL \
  $JAVA_IMAGE \
  java -jar /jars/data-l1.jar run-initial-validator

echo "Waiting 30s for DL1 primary..."
sleep 30

# Get DL1 peer ID
DL1_PEER_ID=$(curl -s http://localhost:9400/node/info | jq -r .id)
echo "DL1 Peer ID: ${DL1_PEER_ID:0:20}..."

# DL1-1
echo "Starting DL1-1..."
docker run -d --name dl1-1 \
  --network $NETWORK \
  -p 9410:9410 -p 9411:9411 -p 9412:9412 \
  -v $JARS_DIR:/jars:ro \
  -v /opt/ottochain/keys3:/keys:ro \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9410 \
  -e CL_P2P_HTTP_PORT=9411 \
  -e CL_CLI_HTTP_PORT=9412 \
  -e CL_EXTERNAL_IP=$HOST_IP \
  -e CL_APP_ENV=$CL_APP_ENV \
  -e CL_GLOBAL_L0_PEER_HTTP_HOST=$HOST_IP \
  -e CL_GLOBAL_L0_PEER_HTTP_PORT=9000 \
  -e CL_GLOBAL_L0_PEER_ID=$GL0_PEER_ID \
  -e CL_L0_PEER_HTTP_HOST=$HOST_IP \
  -e CL_L0_PEER_HTTP_PORT=9200 \
  -e CL_L0_PEER_ID=$ML0_PEER_ID \
  -e CL_L0_TOKEN_IDENTIFIER=$TOKEN_ID \
  -e CL_COLLATERAL=$CL_COLLATERAL \
  $JAVA_IMAGE \
  java -jar /jars/data-l1.jar run-validator

# DL1-2
echo "Starting DL1-2..."
docker run -d --name dl1-2 \
  --network $NETWORK \
  -p 9420:9420 -p 9421:9421 -p 9422:9422 \
  -v $JARS_DIR:/jars:ro \
  -v /opt/ottochain/keys4:/keys:ro \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9420 \
  -e CL_P2P_HTTP_PORT=9421 \
  -e CL_CLI_HTTP_PORT=9422 \
  -e CL_EXTERNAL_IP=$HOST_IP \
  -e CL_APP_ENV=$CL_APP_ENV \
  -e CL_GLOBAL_L0_PEER_HTTP_HOST=$HOST_IP \
  -e CL_GLOBAL_L0_PEER_HTTP_PORT=9000 \
  -e CL_GLOBAL_L0_PEER_ID=$GL0_PEER_ID \
  -e CL_L0_PEER_HTTP_HOST=$HOST_IP \
  -e CL_L0_PEER_HTTP_PORT=9200 \
  -e CL_L0_PEER_ID=$ML0_PEER_ID \
  -e CL_L0_TOKEN_IDENTIFIER=$TOKEN_ID \
  -e CL_COLLATERAL=$CL_COLLATERAL \
  $JAVA_IMAGE \
  java -jar /jars/data-l1.jar run-validator

echo "Waiting 30s for validators..."
sleep 30

# Join validators (CLI port is always 9002 inside container)
echo "Joining DL1-1 to cluster..."
docker exec dl1-1 curl -s -X POST "http://127.0.0.1:9002/cluster/join" \
  -H "Content-Type: application/json" \
  -d "{\"id\": \"$DL1_PEER_ID\", \"ip\": \"$HOST_IP\", \"p2pPort\": 9401}"

echo "Joining DL1-2 to cluster..."
docker exec dl1-2 curl -s -X POST "http://127.0.0.1:9002/cluster/join" \
  -H "Content-Type: application/json" \
  -d "{\"id\": \"$DL1_PEER_ID\", \"ip\": \"$HOST_IP\", \"p2pPort\": 9401}"

sleep 10

echo ""
echo "=== DL1 Cluster Status ==="
echo -n "Cluster size: "
curl -s http://localhost:9400/cluster/info | jq '. | length'
for p in 9400 9410 9420; do
  echo -n "Port $p: "
  curl -s http://localhost:$p/node/info | jq -r .state
done
