#!/bin/bash
# Start CL1 cluster (3 nodes) - Currency Layer
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"

# Reload peer IDs
GL0_PEER_ID=$(cat /opt/ottochain/gl0-peer-id 2>/dev/null || curl -s http://localhost:9000/node/info | jq -r .id)
ML0_PEER_ID=$(cat /opt/ottochain/ml0-peer-id 2>/dev/null || curl -s http://localhost:9200/node/info | jq -r .id)
TOKEN_ID=$(cat /opt/ottochain/token-id 2>/dev/null || echo "")

if [ -z "$GL0_PEER_ID" ] || [ "$GL0_PEER_ID" == "null" ]; then
  echo "ERROR: GL0 must be running"
  exit 1
fi
if [ -z "$ML0_PEER_ID" ] || [ "$ML0_PEER_ID" == "null" ]; then
  echo "ERROR: ML0 must be running"
  exit 1
fi

echo "=== Starting CL1 Cluster (3 nodes) ==="
docker rm -f cl1 cl1-1 cl1-2 2>/dev/null || true

# Optional: clear volumes for fresh genesis
if [ "$1" == "--genesis" ]; then
  echo "Clearing CL1 volumes for fresh genesis..."
  docker volume rm cl1-data cl1-1-data cl1-2-data 2>/dev/null || true
fi

# CL1 Primary (initial-validator)
echo "Starting CL1 primary as initial-validator..."
docker run -d --name cl1 \
  --network $NETWORK \
  --hostname cl1 \
  -p 9300:9300 -p 9301:9301 -p 9302:9302 \
  -v $JARS_DIR:/jars:ro \
  -v $KEYS_DIR:/keys:ro \
  -v cl1-data:/data \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9300 \
  -e CL_P2P_HTTP_PORT=9301 \
  -e CL_CLI_HTTP_PORT=9302 \
  -e CL_EXTERNAL_IP=cl1 \
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
  java -Xmx2g -Xms512m -jar /jars/currency-l1.jar run-initial-validator

# CL1-1
echo "Starting CL1-1..."
docker run -d --name cl1-1 \
  --network $NETWORK \
  --hostname cl1-1 \
  -p 9310:9300 -p 9311:9301 -p 9312:9302 \
  -v $JARS_DIR:/jars:ro \
  -v /opt/ottochain/keys3:/keys:ro \
  -v cl1-1-data:/data \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9300 \
  -e CL_P2P_HTTP_PORT=9301 \
  -e CL_CLI_HTTP_PORT=9302 \
  -e CL_EXTERNAL_IP=cl1-1 \
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
  java -Xmx2g -Xms512m -jar /jars/currency-l1.jar run-validator

# CL1-2
echo "Starting CL1-2..."
docker run -d --name cl1-2 \
  --network $NETWORK \
  --hostname cl1-2 \
  -p 9320:9300 -p 9321:9301 -p 9322:9302 \
  -v $JARS_DIR:/jars:ro \
  -v /opt/ottochain/keys4:/keys:ro \
  -v cl1-2-data:/data \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9300 \
  -e CL_P2P_HTTP_PORT=9301 \
  -e CL_CLI_HTTP_PORT=9302 \
  -e CL_EXTERNAL_IP=cl1-2 \
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
  java -Xmx2g -Xms512m -jar /jars/currency-l1.jar run-validator

echo "Waiting 30s for CL1 nodes..."
sleep 30

# Get CL1 peer ID and join validators
CL1_PEER_ID=$(curl -s http://localhost:9300/node/info | jq -r .id)
echo "CL1 Peer ID: ${CL1_PEER_ID:0:20}..."

echo "Joining CL1-1 to cluster..."
docker exec cl1-1 sh -c "wget -q -O- --post-data='{ \"id\": \"$CL1_PEER_ID\", \"ip\": \"cl1\", \"p2pPort\": 9301 }' --header=\"Content-Type: application/json\" http://127.0.0.1:9302/cluster/join" 2>&1 || true

echo "Joining CL1-2 to cluster..."
docker exec cl1-2 sh -c "wget -q -O- --post-data='{ \"id\": \"$CL1_PEER_ID\", \"ip\": \"cl1\", \"p2pPort\": 9301 }' --header=\"Content-Type: application/json\" http://127.0.0.1:9302/cluster/join" 2>&1 || true

sleep 10

echo ""
echo "=== CL1 Cluster Status ==="
echo -n "Cluster size: "
curl -s http://localhost:9300/cluster/info | jq '. | length'
for p in 9300 9310 9320; do
  echo -n "Port $p: "
  curl -s http://localhost:$p/node/info | jq -r .state
done
