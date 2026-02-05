#!/bin/bash
# Start GL0 cluster (3 nodes)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"

echo "=== Starting GL0 Cluster ==="

# Stop existing
docker rm -f gl0 gl0-1 gl0-2 2>/dev/null || true

# GL0 Primary (genesis mode if no peer ID exists)
if [ -z "$GL0_PEER_ID" ]; then
  echo "Starting GL0 primary in GENESIS mode..."
  MODE="run-genesis /genesis.csv"
  GENESIS_MOUNT="-v /opt/ottochain/genesis.csv:/genesis.csv:ro"
else
  echo "Starting GL0 primary in VALIDATOR mode..."
  MODE="run-validator"
  GENESIS_MOUNT=""
fi

docker run -d --name gl0 \
  --network $NETWORK \
  -p 9000:9000 -p 9001:9001 -p 9002:9002 \
  -v $JARS_DIR:/jars:ro \
  -v $KEYS_DIR:/keys:ro \
  $GENESIS_MOUNT \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9000 \
  -e CL_P2P_HTTP_PORT=9001 \
  -e CL_CLI_HTTP_PORT=9002 \
  -e CL_EXTERNAL_IP=$HOST_IP \
  -e CL_APP_ENV=$CL_APP_ENV \
  -e CL_COLLATERAL=$CL_COLLATERAL \
  $JAVA_IMAGE \
  java -jar /jars/dag-l0.jar $MODE

echo "Waiting 30s for GL0 primary..."
sleep 30

# Save peer ID
GL0_PEER_ID=$(curl -s http://localhost:9000/node/info | jq -r .id)
echo "$GL0_PEER_ID" > /opt/ottochain/gl0-peer-id
echo "GL0 Peer ID: ${GL0_PEER_ID:0:20}..."

# GL0-1
echo "Starting GL0-1..."
docker run -d --name gl0-1 \
  --network $NETWORK \
  -p 9010:9010 -p 9011:9011 -p 9012:9012 \
  -v $JARS_DIR:/jars:ro \
  -v /opt/ottochain/keys5:/keys:ro \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9010 \
  -e CL_P2P_HTTP_PORT=9011 \
  -e CL_CLI_HTTP_PORT=9012 \
  -e CL_EXTERNAL_IP=$HOST_IP \
  -e CL_APP_ENV=$CL_APP_ENV \
  -e CL_GLOBAL_L0_PEER_HTTP_HOST=$HOST_IP \
  -e CL_GLOBAL_L0_PEER_HTTP_PORT=9000 \
  -e CL_GLOBAL_L0_PEER_ID=$GL0_PEER_ID \
  -e CL_COLLATERAL=$CL_COLLATERAL \
  $JAVA_IMAGE \
  java -jar /jars/dag-l0.jar run-validator

# GL0-2
echo "Starting GL0-2..."
docker run -d --name gl0-2 \
  --network $NETWORK \
  -p 9020:9020 -p 9021:9021 -p 9022:9022 \
  -v $JARS_DIR:/jars:ro \
  -v /opt/ottochain/keys6:/keys:ro \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9020 \
  -e CL_P2P_HTTP_PORT=9021 \
  -e CL_CLI_HTTP_PORT=9022 \
  -e CL_EXTERNAL_IP=$HOST_IP \
  -e CL_APP_ENV=$CL_APP_ENV \
  -e CL_GLOBAL_L0_PEER_HTTP_HOST=$HOST_IP \
  -e CL_GLOBAL_L0_PEER_HTTP_PORT=9000 \
  -e CL_GLOBAL_L0_PEER_ID=$GL0_PEER_ID \
  -e CL_COLLATERAL=$CL_COLLATERAL \
  $JAVA_IMAGE \
  java -jar /jars/dag-l0.jar run-validator

echo "Waiting 30s for validators..."
sleep 30

# Join validators (use the CLI port each container listens on internally)
echo "Joining GL0-1 to cluster..."
docker exec gl0-1 curl -s -X POST "http://127.0.0.1:9012/cluster/join" \
  -H "Content-Type: application/json" \
  -d "{\"id\": \"$GL0_PEER_ID\", \"ip\": \"$HOST_IP\", \"p2pPort\": 9001}"

echo "Joining GL0-2 to cluster..."
docker exec gl0-2 curl -s -X POST "http://127.0.0.1:9022/cluster/join" \
  -H "Content-Type: application/json" \
  -d "{\"id\": \"$GL0_PEER_ID\", \"ip\": \"$HOST_IP\", \"p2pPort\": 9001}"

sleep 10

echo ""
echo "=== GL0 Cluster Status ==="
echo -n "Cluster size: "
curl -s http://localhost:9000/cluster/info | jq '. | length'
for p in 9000 9010 9020; do
  echo -n "Port $p: "
  curl -s http://localhost:$p/node/info | jq -r .state
done
