#!/bin/bash
# Start ML0 cluster (3 nodes)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"

echo "=== Starting ML0 Cluster ==="

# Check for genesis snapshot
if [ ! -f "$DATA_DIR/genesis.snapshot" ]; then
  echo "ERROR: Genesis snapshot not found at $DATA_DIR/genesis.snapshot"
  echo "Create it with: java -jar jars/metagraph-l0.jar create-genesis genesis.csv"
  exit 1
fi

# Stop existing
docker rm -f ml0 ml0-1 ml0-2 2>/dev/null || true

# ML0 Primary (genesis mode if no peer ID exists)
if [ -z "$ML0_PEER_ID" ]; then
  echo "Starting ML0 primary in GENESIS mode..."
  MODE="run-genesis /data/genesis.snapshot"
else
  echo "Starting ML0 primary in VALIDATOR mode..."
  MODE="run-validator"
fi

docker run -d --name ml0 \
  --network $NETWORK \
  -p 9200:9200 -p 9201:9201 -p 9202:9202 \
  -v $JARS_DIR:/jars:ro \
  -v $KEYS_DIR:/keys:ro \
  -v $DATA_DIR:/data \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9200 \
  -e CL_P2P_HTTP_PORT=9201 \
  -e CL_CLI_HTTP_PORT=9202 \
  -e CL_EXTERNAL_IP=$HOST_IP \
  -e CL_APP_ENV=$CL_APP_ENV \
  -e CL_GLOBAL_L0_PEER_HTTP_HOST=$HOST_IP \
  -e CL_GLOBAL_L0_PEER_HTTP_PORT=9000 \
  -e CL_GLOBAL_L0_PEER_ID=$GL0_PEER_ID \
  -e CL_COLLATERAL=$CL_COLLATERAL \
  $JAVA_IMAGE \
  java -jar /jars/metagraph-l0.jar $MODE

echo "Waiting 30s for ML0 primary..."
sleep 30

# Save peer ID and token ID
ML0_PEER_ID=$(curl -s http://localhost:9200/node/info | jq -r .id)
echo "$ML0_PEER_ID" > /opt/ottochain/ml0-peer-id
echo "ML0 Peer ID: ${ML0_PEER_ID:0:20}..."

# Get token ID from state channel
TOKEN_ID=$(curl -s http://localhost:9000/global-snapshots/latest | jq -r '.value.stateChannelSnapshots | keys[0]' 2>/dev/null || echo "")
if [ -n "$TOKEN_ID" ] && [ "$TOKEN_ID" != "null" ]; then
  echo "$TOKEN_ID" > /opt/ottochain/token-id
  echo "Token ID: ${TOKEN_ID:0:20}..."
fi

# Reload TOKEN_ID for validators
TOKEN_ID=$(cat /opt/ottochain/token-id 2>/dev/null || echo "")

# ML0-1
echo "Starting ML0-1..."
docker run -d --name ml0-1 \
  --network $NETWORK \
  -p 9210:9210 -p 9211:9211 -p 9212:9212 \
  -v $JARS_DIR:/jars:ro \
  -v /opt/ottochain/keys7:/keys:ro \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9210 \
  -e CL_P2P_HTTP_PORT=9211 \
  -e CL_CLI_HTTP_PORT=9212 \
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
  java -jar /jars/metagraph-l0.jar run-validator

# ML0-2
echo "Starting ML0-2..."
docker run -d --name ml0-2 \
  --network $NETWORK \
  -p 9220:9220 -p 9221:9221 -p 9222:9222 \
  -v $JARS_DIR:/jars:ro \
  -v /opt/ottochain/keys8:/keys:ro \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9220 \
  -e CL_P2P_HTTP_PORT=9221 \
  -e CL_CLI_HTTP_PORT=9222 \
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
  java -jar /jars/metagraph-l0.jar run-validator

echo "Waiting 40s for validators..."
sleep 40

# Join validators
echo "Joining ML0-1 to cluster..."
docker exec ml0-1 curl -s -X POST "http://127.0.0.1:9212/cluster/join" \
  -H "Content-Type: application/json" \
  -d "{\"id\": \"$ML0_PEER_ID\", \"ip\": \"$HOST_IP\", \"p2pPort\": 9201}"

echo "Joining ML0-2 to cluster..."
docker exec ml0-2 curl -s -X POST "http://127.0.0.1:9222/cluster/join" \
  -H "Content-Type: application/json" \
  -d "{\"id\": \"$ML0_PEER_ID\", \"ip\": \"$HOST_IP\", \"p2pPort\": 9201}"

sleep 10

echo ""
echo "=== ML0 Cluster Status ==="
echo -n "Cluster size: "
curl -s http://localhost:9200/cluster/info | jq '. | length'
for p in 9200 9210 9220; do
  echo -n "Port $p: "
  curl -s http://localhost:$p/node/info | jq -r .state
done
