#!/bin/bash
# Start CL1 cluster (3 nodes) - Currency Layer 1
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"

# Reload peer IDs
GL0_PEER_ID=$(cat /opt/ottochain/gl0-peer-id)
ML0_PEER_ID=$(cat /opt/ottochain/ml0-peer-id)
TOKEN_ID=$(cat /opt/ottochain/token-id)

echo "=== Starting CL1 Cluster ==="
echo "TOKEN_ID: $TOKEN_ID"

# Stop existing
docker rm -f cl1 cl1-1 cl1-2 2>/dev/null || true

# CL1 Primary (initial-validator)
echo "Starting CL1 primary as initial-validator..."
docker run -d --name cl1 \
  --network $NETWORK \
  -p 9300:9300 -p 9301:9301 -p 9302:9302 \
  -v $JARS_DIR:/jars:ro \
  -v /opt/ottochain/keys5:/keys:ro \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9300 \
  -e CL_P2P_HTTP_PORT=9301 \
  -e CL_CLI_HTTP_PORT=9302 \
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
  java -jar /jars/currency-l1.jar run-initial-validator

echo "Waiting 30s for CL1 primary..."
sleep 30

# Get CL1 peer ID
CL1_PEER_ID=$(curl -s http://localhost:9300/node/info | jq -r .id)
echo "CL1 Peer ID: ${CL1_PEER_ID:0:20}..."
echo "$CL1_PEER_ID" > /opt/ottochain/cl1-peer-id

# CL1-1
echo "Starting CL1-1..."
docker run -d --name cl1-1 \
  --network $NETWORK \
  -p 9310:9310 -p 9311:9311 -p 9312:9312 \
  -v $JARS_DIR:/jars:ro \
  -v /opt/ottochain/keys6:/keys:ro \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9310 \
  -e CL_P2P_HTTP_PORT=9311 \
  -e CL_CLI_HTTP_PORT=9312 \
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
  java -jar /jars/currency-l1.jar run-validator

# CL1-2
echo "Starting CL1-2..."
docker run -d --name cl1-2 \
  --network $NETWORK \
  -p 9320:9320 -p 9321:9321 -p 9322:9322 \
  -v $JARS_DIR:/jars:ro \
  -v /opt/ottochain/keys7:/keys:ro \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9320 \
  -e CL_P2P_HTTP_PORT=9321 \
  -e CL_CLI_HTTP_PORT=9322 \
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
  java -jar /jars/currency-l1.jar run-validator

echo "Waiting 30s for validators..."
sleep 30

# Join validators (CLI port is always 9002 inside container)
echo "Joining CL1-1 to cluster..."
docker exec cl1-1 curl -s -X POST "http://127.0.0.1:9002/cluster/join" \
  -H "Content-Type: application/json" \
  -d "{\"id\": \"$CL1_PEER_ID\", \"ip\": \"$HOST_IP\", \"p2pPort\": 9301}"

echo "Joining CL1-2 to cluster..."
docker exec cl1-2 curl -s -X POST "http://127.0.0.1:9002/cluster/join" \
  -H "Content-Type: application/json" \
  -d "{\"id\": \"$CL1_PEER_ID\", \"ip\": \"$HOST_IP\", \"p2pPort\": 9301}"

sleep 10

echo ""
echo "=== CL1 Cluster Status ==="
echo -n "Cluster size: "
curl -s http://localhost:9300/cluster/info | jq '. | length'
for p in 9300 9310 9320; do
  echo -n "Port $p: "
  curl -s http://localhost:$p/node/info | jq -r .state
done
