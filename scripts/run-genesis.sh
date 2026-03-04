#!/usr/bin/env bash
# Run the full genesis sequence: GL0 genesis → ML0 genesis → genesis files ready
# Must be run on node1 (the genesis node).
#
# Prerequisites:
#   - Docker image pulled
#   - Keys at /opt/ottochain/keys/key.p12
#   - Environment variables: CL_PASSWORD, EXTERNAL_IP, IMAGE, GL0_PEER_ID
#
# Produces:
#   - /opt/ottochain/genesis/genesis.address (TOKEN_ID)
#   - /opt/ottochain/genesis/genesis.snapshot
#   - /opt/ottochain/genesis/gl0-genesis.csv

set -euo pipefail

# Required env vars
: "${CL_PASSWORD:?CL_PASSWORD required}"
: "${EXTERNAL_IP:?EXTERNAL_IP required}"
: "${IMAGE:?IMAGE required (e.g. ghcr.io/scasplte2/ottochain-metagraph:latest)}"
: "${GL0_PEER_ID:?GL0_PEER_ID required (from extract-peer-id.sh)}"

GENESIS_DIR="/opt/ottochain/genesis"
KEYS_DIR="/opt/ottochain/keys"

echo "=== OttoChain Genesis Sequence ==="
echo "Image:    $IMAGE"
echo "Node IP:  $EXTERNAL_IP"
echo "Peer ID:  ${GL0_PEER_ID:0:32}..."

# Step 1: Wipe old state
echo ""
echo "--- Step 1: Wipe old state ---"
rm -rf /opt/ottochain/{gl0,gl1,ml0,cl1,dl1}-data
rm -rf /opt/ottochain/{gl0,gl1,ml0,cl1,dl1}-logs
rm -rf "${GENESIS_DIR}"/*
mkdir -p /opt/ottochain/{gl0,ml0,dl1}-data
mkdir -p /opt/ottochain/{gl0,ml0,dl1}-logs
mkdir -p "${GENESIS_DIR}"
echo "✓ State wiped"

# Step 2: Get wallet address and create GL0 genesis CSV
echo ""
echo "--- Step 2: Create GL0 genesis CSV ---"
WALLET=$(CL_KEYSTORE="${KEYS_DIR}/key.p12" CL_KEYALIAS=alias CL_PASSWORD="${CL_PASSWORD}" \
  java -jar /opt/ottochain/cl-wallet.jar show-address 2>&1 | grep -oP 'DAG[a-zA-Z0-9]+' | head -1)

if [ -z "$WALLET" ]; then
  echo "❌ Failed to extract wallet address"
  exit 1
fi
echo "${WALLET},1000000000000000" > "${GENESIS_DIR}/gl0-genesis.csv"
echo "✓ GL0 genesis CSV created (wallet: $WALLET)"

# Step 3: Start GL0 in genesis mode
echo ""
echo "--- Step 3: Start GL0 (genesis mode) ---"
docker rm -f gl0 2>/dev/null || true
docker run -d --name gl0 \
  -p 9000:9000 -p 9001:9001 -p 9002:9002 \
  -v "${KEYS_DIR}":/ottochain/keys:ro \
  -v /opt/ottochain/gl0-data:/ottochain/data \
  -v /opt/ottochain/gl0-logs:/ottochain/logs \
  -v "${GENESIS_DIR}":/ottochain/genesis:ro \
  -e LAYER=gl0 \
  -e IS_INITIAL=true \
  -e CL_APP_ENV=dev \
  -e CL_EXTERNAL_IP="${EXTERNAL_IP}" \
  -e CL_COLLATERAL=0 \
  -e CL_KEYSTORE=/ottochain/keys/key.p12 \
  -e CL_KEYALIAS=alias \
  -e CL_PASSWORD="${CL_PASSWORD}" \
  -e JAVA_OPTS="-Xmx3g -Xms2g -XX:+UseZGC -XX:MaxMetaspaceSize=256m -XX:MaxDirectMemorySize=256m -XX:ReservedCodeCacheSize=128m -XX:+ExitOnOutOfMemoryError -XX:+UseStringDeduplication -XX:SoftRefLRUPolicyMSPerMB=50 -XX:ZUncommitDelay=60" \
  "${IMAGE}"
echo "✓ GL0 container started"

# Step 4: Wait for GL0 Ready
echo ""
echo "--- Step 4: Wait for GL0 Ready ---"
for i in $(seq 1 90); do
  state=$(curl -sf http://localhost:9000/node/info 2>/dev/null | jq -r .state 2>/dev/null || echo "")
  if [ "$state" = "Ready" ]; then
    echo "✓ GL0 is Ready (attempt $i)"
    break
  fi
  if [ "$i" = "90" ]; then
    echo "❌ GL0 failed to reach Ready after 90 attempts"
    docker logs gl0 --tail 20
    exit 1
  fi
  sleep 5
done

# Step 5: Create ML0 genesis snapshot (requires GL0 running)
echo ""
echo "--- Step 5: Create ML0 genesis snapshot ---"
docker run --rm \
  --network host \
  --entrypoint '' \
  -v "${KEYS_DIR}":/ottochain/keys:ro \
  -v "${GENESIS_DIR}":/ottochain/genesis \
  -w /ottochain/genesis \
  -e CL_KEYSTORE=/ottochain/keys/key.p12 \
  -e CL_KEYALIAS=alias \
  -e CL_PASSWORD="${CL_PASSWORD}" \
  -e CL_GLOBAL_L0_PEER_ID="${GL0_PEER_ID}" \
  -e CL_GLOBAL_L0_PEER_HOST="${EXTERNAL_IP}" \
  -e CL_GLOBAL_L0_PEER_PORT=9000 \
  -e CL_GLOBAL_L0_PEER_HTTP_HOST="${EXTERNAL_IP}" \
  -e CL_GLOBAL_L0_PEER_HTTP_PORT=9000 \
  -e CL_PUBLIC_HTTP_PORT=9200 \
  -e CL_P2P_HTTP_PORT=9201 \
  -e CL_CLI_HTTP_PORT=9202 \
  -e CL_COLLATERAL=0 \
  -e CL_APP_ENV=dev \
  -e CL_EXTERNAL_IP="${EXTERNAL_IP}" \
  "${IMAGE}" \
  java -jar /ottochain/jars/ml0.jar create-genesis /ottochain/genesis/genesis.csv

# Verify
if [ ! -f "${GENESIS_DIR}/genesis.snapshot" ] || [ ! -f "${GENESIS_DIR}/genesis.address" ]; then
  echo "❌ ML0 genesis failed — missing genesis.snapshot or genesis.address"
  exit 1
fi

TOKEN_ID=$(cat "${GENESIS_DIR}/genesis.address")
echo "✓ ML0 genesis complete"
echo "  genesis.snapshot: $(ls -la ${GENESIS_DIR}/genesis.snapshot)"
echo "  TOKEN_ID: $TOKEN_ID"

# Step 6: Stop GL0 (compose will restart it properly)
echo ""
echo "--- Step 6: Stop genesis GL0 ---"
docker rm -f gl0
echo "✓ Genesis GL0 stopped"

echo ""
echo "=== Genesis Complete ==="
echo "TOKEN_ID=$TOKEN_ID"
echo ""
echo "Genesis files ready at ${GENESIS_DIR}/"
echo "Next: distribute genesis files to node2/node3, then docker compose up"
