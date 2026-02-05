#!/bin/bash
# Start DL1 cluster (3 nodes) - Data Layer
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"

# Reload peer IDs
GL0_PEER_ID=$(cat /opt/ottochain/gl0-peer-id)
ML0_PEER_ID=$(cat /opt/ottochain/ml0-peer-id)
TOKEN_ID=$(cat /opt/ottochain/token-id)

if [ -z "$GL0_PEER_ID" ] || [ "$GL0_PEER_ID" == "null" ]; then
  echo "ERROR: GL0 must be running (no gl0-peer-id found)"
  exit 1
fi
if [ -z "$ML0_PEER_ID" ] || [ "$ML0_PEER_ID" == "null" ]; then
  echo "ERROR: ML0 must be running (no ml0-peer-id found)"
  exit 1
fi
if [ -z "$TOKEN_ID" ] || [ "$TOKEN_ID" == "null" ]; then
  echo "ERROR: TOKEN_ID not found - run ML0 genesis first"
  exit 1
fi

echo "=== Starting DL1 Cluster ==="
echo "GL0_PEER_ID: ${GL0_PEER_ID:0:20}..."
echo "ML0_PEER_ID: ${ML0_PEER_ID:0:20}..."
echo "TOKEN_ID: ${TOKEN_ID:0:20}..."

# Stop existing
docker rm -f dl1 dl1-1 dl1-2 2>/dev/null || true

# Optional: clear volumes for fresh genesis
if [ "$1" == "--genesis" ]; then
  echo "Clearing DL1 volumes for fresh genesis..."
  docker volume rm dl1-data dl1-1-data dl1-2-data 2>/dev/null || true
fi

# DL1 Primary (initial-validator)
echo "Starting DL1 primary as initial-validator..."
docker run -d --name dl1 \
  --network $NETWORK \
  --hostname dl1 \
  -p 9400:9400 -p 9401:9401 -p 9402:9402 \
  -v $JARS_DIR:/jars:ro \
  -v $KEYS_DIR:/keys:ro \
  -v dl1-data:/data \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9400 \
  -e CL_P2P_HTTP_PORT=9401 \
  -e CL_CLI_HTTP_PORT=9402 \
  -e CL_EXTERNAL_IP=dl1 \
  -e CL_APP_ENV=$CL_APP_ENV \
  -e CL_GLOBAL_L0_PEER_HTTP_HOST=gl0 \
  -e CL_GLOBAL_L0_PEER_HTTP_PORT=9000 \
  -e CL_GLOBAL_L0_PEER_ID=$GL0_PEER_ID \
  -e CL_L0_PEER_HTTP_HOST=ml0 \
  -e CL_L0_PEER_HTTP_PORT=9200 \
  -e CL_L0_PEER_ID=$ML0_PEER_ID \
  -e CL_L0_TOKEN_IDENTIFIER=$TOKEN_ID \
  -e CL_COLLATERAL=$CL_COLLATERAL \
  $JAVA_IMAGE \
  java -Xmx2g -Xms512m -jar /jars/data-l1.jar run-initial-validator

echo "Waiting 30s for DL1 primary..."
sleep 30

# Get DL1 peer ID
DL1_PEER_ID=$(curl -s http://localhost:9400/node/info | jq -r .id)
echo "DL1 Peer ID: ${DL1_PEER_ID:0:20}..."

# DL1-1
echo "Starting DL1-1..."
docker run -d --name dl1-1 \
  --network $NETWORK \
  --hostname dl1-1 \
  -p 9410:9400 -p 9411:9401 -p 9412:9402 \
  -v $JARS_DIR:/jars:ro \
  -v /opt/ottochain/keys3:/keys:ro \
  -v dl1-1-data:/data \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9400 \
  -e CL_P2P_HTTP_PORT=9401 \
  -e CL_CLI_HTTP_PORT=9402 \
  -e CL_EXTERNAL_IP=dl1-1 \
  -e CL_APP_ENV=$CL_APP_ENV \
  -e CL_GLOBAL_L0_PEER_HTTP_HOST=gl0 \
  -e CL_GLOBAL_L0_PEER_HTTP_PORT=9000 \
  -e CL_GLOBAL_L0_PEER_ID=$GL0_PEER_ID \
  -e CL_L0_PEER_HTTP_HOST=ml0 \
  -e CL_L0_PEER_HTTP_PORT=9200 \
  -e CL_L0_PEER_ID=$ML0_PEER_ID \
  -e CL_L0_TOKEN_IDENTIFIER=$TOKEN_ID \
  -e CL_COLLATERAL=$CL_COLLATERAL \
  $JAVA_IMAGE \
  java -Xmx2g -Xms512m -jar /jars/data-l1.jar run-validator

# DL1-2
echo "Starting DL1-2..."
docker run -d --name dl1-2 \
  --network $NETWORK \
  --hostname dl1-2 \
  -p 9420:9400 -p 9421:9401 -p 9422:9402 \
  -v $JARS_DIR:/jars:ro \
  -v /opt/ottochain/keys4:/keys:ro \
  -v dl1-2-data:/data \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9400 \
  -e CL_P2P_HTTP_PORT=9401 \
  -e CL_CLI_HTTP_PORT=9402 \
  -e CL_EXTERNAL_IP=dl1-2 \
  -e CL_APP_ENV=$CL_APP_ENV \
  -e CL_GLOBAL_L0_PEER_HTTP_HOST=gl0 \
  -e CL_GLOBAL_L0_PEER_HTTP_PORT=9000 \
  -e CL_GLOBAL_L0_PEER_ID=$GL0_PEER_ID \
  -e CL_L0_PEER_HTTP_HOST=ml0 \
  -e CL_L0_PEER_HTTP_PORT=9200 \
  -e CL_L0_PEER_ID=$ML0_PEER_ID \
  -e CL_L0_TOKEN_IDENTIFIER=$TOKEN_ID \
  -e CL_COLLATERAL=$CL_COLLATERAL \
  $JAVA_IMAGE \
  java -Xmx2g -Xms512m -jar /jars/data-l1.jar run-validator

echo "Waiting 30s for validators..."
sleep 30

# Join validators (use wget since curl may not be in the image)
echo "Joining DL1-1 to cluster..."
docker exec dl1-1 sh -c "wget -q -O- --post-data='{ \"id\": \"$DL1_PEER_ID\", \"ip\": \"dl1\", \"p2pPort\": 9401 }' --header=\"Content-Type: application/json\" http://127.0.0.1:9402/cluster/join" 2>&1 || true

echo "Joining DL1-2 to cluster..."
docker exec dl1-2 sh -c "wget -q -O- --post-data='{ \"id\": \"$DL1_PEER_ID\", \"ip\": \"dl1\", \"p2pPort\": 9401 }' --header=\"Content-Type: application/json\" http://127.0.0.1:9402/cluster/join" 2>&1 || true

sleep 10

echo ""
echo "=== DL1 Cluster Status ==="
echo -n "Cluster size: "
curl -s http://localhost:9400/cluster/info | jq '. | length'
for p in 9400 9410 9420; do
  echo -n "Port $p: "
  curl -s http://localhost:$p/node/info | jq -r .state
done
