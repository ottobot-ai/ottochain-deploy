#!/bin/bash
set -euo pipefail

# Local Cluster Setup — generates keys, genesis, starts everything, joins clusters
#
# Usage:
#   cd test/local
#   ./setup.sh [--skip-genesis] [--image-tag TAG]
#
# Prerequisites:
#   docker login ghcr.io  (for private images)

cd "$(dirname "$0")"

IMAGE="ghcr.io/scasplte2/ottochain-metagraph"
IMAGE_TAG="0.7.9"
SERVICES_IMAGE="ghcr.io/ottobot-ai/ottochain-services:latest"
EXPLORER_IMAGE="ghcr.io/ottobot-ai/ottochain-explorer:latest"
TESS_VERSION="${TESS_VERSION:-4.0.0-rc.10}"
SKIP_GENESIS=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --image-tag) IMAGE_TAG="$2"; shift 2 ;;
    --skip-genesis) SKIP_GENESIS=true; shift ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

FULL_IMAGE="${IMAGE}:${IMAGE_TAG}"
TOOLS_DIR="./data/tools"
KEYS_DIR="./data/keys"
GENESIS_DIR="./data/genesis"

step() { echo ""; echo "═══ $1 ═══"; }

# ── Genesis ──────────────────────────────────────────────────────────────
if [ "$SKIP_GENESIS" = "false" ]; then
  step "Preparing genesis"

  mkdir -p "$TOOLS_DIR" "$KEYS_DIR/node1" "$KEYS_DIR/node2" "$KEYS_DIR/node3" "$GENESIS_DIR"

  # Download tessellation tools
  for jar in cl-keytool.jar cl-wallet.jar; do
    if [ ! -f "$TOOLS_DIR/$jar" ]; then
      echo "  Downloading $jar..."
      curl -sL -o "$TOOLS_DIR/$jar" \
        "https://github.com/Constellation-Labs/tessellation/releases/download/v${TESS_VERSION}/$jar"
    fi
  done

  # Generate keystores for each node
  for i in 1 2 3; do
    if [ ! -f "$KEYS_DIR/node$i/key.p12" ]; then
      echo "  Generating keystore for node$i..."
      docker run --rm \
        -v "$(pwd)/$KEYS_DIR/node$i:/keys" \
        -v "$(pwd)/$TOOLS_DIR:/tools:ro" \
        -e CL_KEYSTORE=/keys/key.p12 \
        -e CL_KEYALIAS=alias \
        -e CL_PASSWORD=testpass \
        --entrypoint '' \
        "$FULL_IMAGE" java -jar /tools/cl-keytool.jar generate
      echo "  ✅ node$i keystore"
    fi
  done

  # Extract peer ID from node1
  echo "  Extracting peer ID..."
  GL0_PEER_ID=$(docker run --rm \
    -v "$(pwd)/$KEYS_DIR/node1:/keys:ro" \
    -v "$(pwd)/$TOOLS_DIR:/tools:ro" \
    -e CL_KEYSTORE=/keys/key.p12 \
    -e CL_KEYALIAS=alias \
    -e CL_PASSWORD=testpass \
    --entrypoint '' \
    "$FULL_IMAGE" java -jar /tools/cl-wallet.jar show-id 2>/dev/null)
  echo "  Peer ID: ${GL0_PEER_ID:0:32}..."

  # Extract wallet for genesis CSV
  WALLET=$(docker run --rm \
    -v "$(pwd)/$KEYS_DIR/node1:/keys:ro" \
    -v "$(pwd)/$TOOLS_DIR:/tools:ro" \
    -e CL_KEYSTORE=/keys/key.p12 \
    -e CL_KEYALIAS=alias \
    -e CL_PASSWORD=testpass \
    --entrypoint '' \
    "$FULL_IMAGE" java -jar /tools/cl-wallet.jar show-address 2>/dev/null | grep -oP 'DAG[a-zA-Z0-9]+' | head -1)
  echo "  Wallet: $WALLET"

  echo "${WALLET},1000000000000000" > "$GENESIS_DIR/genesis.csv"

  # GL0 genesis — start temporary GL0 to generate genesis snapshot
  step "GL0 genesis"
  docker rm -f gl0-genesis 2>/dev/null || true
  docker run -d --name gl0-genesis --network host \
    -v "$(pwd)/$KEYS_DIR/node1:/ottochain/keys:ro" \
    -v "$(pwd)/$GENESIS_DIR:/ottochain/genesis:ro" \
    -e LAYER=gl0 -e IS_INITIAL=true -e CL_APP_ENV=dev \
    -e CL_EXTERNAL_IP=127.0.0.1 -e CL_COLLATERAL=0 \
    -e CL_KEYSTORE=/ottochain/keys/key.p12 -e CL_KEYALIAS=alias \
    -e CL_PASSWORD=testpass -e JAVA_OPTS='-Xmx1g -Xms512m' \
    "$FULL_IMAGE"

  echo "  Waiting for GL0 Ready..."
  for i in $(seq 1 60); do
    state=$(docker exec gl0-genesis wget -qO- http://127.0.0.1:9000/node/info 2>/dev/null | grep -o '"state":"[^"]*"' | cut -d'"' -f4 || echo "")
    if [ "$state" = "Ready" ]; then echo "  ✅ GL0 Ready (${i}x5s)"; break; fi
    [ "$i" = "60" ] && { echo "  ❌ GL0 timeout"; docker logs gl0-genesis --tail 20; exit 1; }
    sleep 5
  done

  # ML0 genesis snapshot
  step "ML0 genesis snapshot"
  docker run --rm --network host --entrypoint '' \
    -v "$(pwd)/$KEYS_DIR/node1:/ottochain/keys:ro" \
    -v "$(pwd)/$GENESIS_DIR:/ottochain/genesis" \
    -w /ottochain/genesis \
    -e CL_KEYSTORE=/ottochain/keys/key.p12 -e CL_KEYALIAS=alias -e CL_PASSWORD=testpass \
    -e CL_GLOBAL_L0_PEER_ID=${GL0_PEER_ID} \
    -e CL_GLOBAL_L0_PEER_HOST=127.0.0.1 -e CL_GLOBAL_L0_PEER_PORT=9000 \
    -e CL_GLOBAL_L0_PEER_HTTP_HOST=127.0.0.1 -e CL_GLOBAL_L0_PEER_HTTP_PORT=9000 \
    -e CL_PUBLIC_HTTP_PORT=9200 -e CL_P2P_HTTP_PORT=9201 -e CL_CLI_HTTP_PORT=9202 \
    -e CL_COLLATERAL=0 -e CL_APP_ENV=dev -e CL_EXTERNAL_IP=127.0.0.1 \
    "$FULL_IMAGE" java -jar /ottochain/jars/ml0.jar create-genesis /ottochain/genesis/genesis.csv

  TOKEN_ID=$(cat "$GENESIS_DIR/genesis.address" 2>/dev/null || echo "")
  if [ -n "$TOKEN_ID" ]; then
    echo "  ✅ Token ID: $TOKEN_ID"
  else
    echo "  ❌ ML0 genesis failed"; exit 1
  fi

  docker rm -f gl0-genesis 2>/dev/null

  # Write .env
  cat > .env << EOF
IMAGE=${FULL_IMAGE}
SERVICES_IMAGE=${SERVICES_IMAGE}
EXPLORER_IMAGE=${EXPLORER_IMAGE}
GL0_PEER_ID=${GL0_PEER_ID}
TOKEN_ID=${TOKEN_ID}
CL_PASSWORD=testpass
EOF
  echo "  ✅ .env written"

else
  # Load existing .env
  source .env
  GL0_PEER_ID="${GL0_PEER_ID}"
fi

# ── Start cluster ────────────────────────────────────────────────────────
step "Starting cluster"
docker compose up -d
echo "  Waiting for services to start..."
sleep 10

# ── Cluster join ─────────────────────────────────────────────────────────
wait_ready() {
  local container="$1" port="$2" max="${3:-60}"
  for i in $(seq 1 "$max"); do
    state=$(docker exec "$container" wget -qO- "http://127.0.0.1:${port}/node/info" 2>/dev/null | grep -o '"state":"[^"]*"' | cut -d'"' -f4 || echo "")
    [ "$state" = "Ready" ] && return 0
    [ "$state" = "ReadyToJoin" ] && return 0
    sleep 5
  done
  return 1
}

join_layer() {
  local layer="$1" cli_port="$2" p2p_port="$3" peer_ip="$4"
  step "Join $layer cluster"
  
  # Wait for node1 to be Ready
  echo "  Waiting for ${layer}-1 Ready..."
  for i in $(seq 1 60); do
    state=$(docker exec "${layer}-1" wget -qO- "http://127.0.0.1:${cli_port}/node/info" 2>/dev/null | grep -o '"state":"[^"]*"' | cut -d'"' -f4 || echo "")
    if [ "$state" = "Ready" ]; then echo "  ✅ ${layer}-1 Ready"; break; fi
    [ "$i" = "60" ] && { echo "  ❌ ${layer}-1 timeout"; docker logs "${layer}-1" --tail 10; return 1; }
    sleep 5
  done

  # Join nodes 2 and 3
  for n in 2 3; do
    echo "  Joining ${layer}-${n}..."
    for j in $(seq 1 30); do
      state=$(docker exec "${layer}-${n}" wget -qO- "http://127.0.0.1:${cli_port}/node/info" 2>/dev/null | grep -o '"state":"[^"]*"' | cut -d'"' -f4 || echo "")
      [ "$state" = "ReadyToJoin" ] || [ "$state" = "Ready" ] && break
      sleep 5
    done
    # Find peer ID for node1
    PEER_ID=$(docker exec "${layer}-1" wget -qO- "http://127.0.0.1:${cli_port}/node/info" 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "$GL0_PEER_ID")
    docker exec "${layer}-${n}" wget -qO- --post-data="{\"id\":\"${PEER_ID}\",\"ip\":\"${peer_ip}\",\"p2pPort\":${p2p_port}}" \
      --header='Content-Type: application/json' "http://127.0.0.1:${cli_port}/cluster/join" 2>/dev/null || true
    echo "  ✅ ${layer}-${n} join sent"
  done
}

join_layer gl0 9002 9001 172.30.0.11
join_layer ml0 9202 9201 172.30.0.21
join_layer dl1 9402 9401 172.30.0.31

# ── Status ───────────────────────────────────────────────────────────────
step "Cluster Status"
sleep 15  # Let joins propagate

for layer_port in "gl0:9000" "ml0:9200" "dl1:9400"; do
  layer="${layer_port%%:*}"
  port="${layer_port##*:}"
  echo "  $layer:"
  for n in 1 2 3; do
    state=$(docker exec "${layer}-${n}" wget -qO- "http://127.0.0.1:${port}/node/info" 2>/dev/null | grep -o '"state":"[^"]*"' | cut -d'"' -f4 || echo "DOWN")
    icon="✅"; [ "$state" != "Ready" ] && icon="⚠️ "
    echo "    $icon ${layer}-${n}: $state"
  done
done

echo ""
echo "═══ Access Points ═══"
echo "  Explorer:  http://localhost:8080"
echo "  Gateway:   http://localhost:4000"
echo "  Bridge:    http://localhost:3030"
echo "  Indexer:   http://localhost:3031"
echo "  Traffic:   http://localhost:3033/status"
echo "  GL0:       http://localhost:9000  (via docker — not port-mapped)"
echo ""
echo "  Traffic generator auto-started at 2 TPS"
