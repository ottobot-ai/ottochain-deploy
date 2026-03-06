#!/bin/bash
set -euo pipefail

# ⚠️  LEGACY: Docker-in-Docker entry point (superseded by setup.sh)
#
# This script is the original DinD-based test harness. It is retained for
# reference but is NOT the active entry point for this PR. Use setup.sh
# for the plain-container approach (simpler, no nested Docker required).
#
# See also: PR #166 (feat/local-deploy-test) which this branch supersedes.
#
# Local Deploy Test — Docker-in-Docker
#
# Tests the metagraph deploy workflow locally against 3 DinD containers.
#
# Usage:
#   cd test/local
#   docker compose up -d
#   # Pre-pull image: for n in test-node{1,2,3}; do docker exec $n docker pull ghcr.io/...; done
#   ./run-deploy-test.sh [--image-tag TAG] [--no-wipe] [--skip-genesis]
#
# NOTE on DinD volume mounts:
#   Inner containers (inside DinD) cannot `-v /opt/ottochain/...` because that
#   path resolves on the DinD rootfs, not the named volume. We use a shared
#   Docker volume named "shared-data" that both DinD host and inner containers mount.

IMAGE="ghcr.io/scasplte2/ottochain-metagraph"
IMAGE_TAG="0.7.9"
WIPE=true
SKIP_GENESIS=false
NODES=("test-node1" "test-node2" "test-node3")
NODE_IPS=("172.28.0.11" "172.28.0.12" "172.28.0.13")
TESS_VERSION="${TESS_VERSION:-4.0.0-rc.10}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

while [[ $# -gt 0 ]]; do
  case $1 in
    --image-tag) IMAGE_TAG="$2"; shift 2 ;;
    --wipe) WIPE=true; shift ;;
    --no-wipe) WIPE=false; shift ;;
    --skip-genesis) SKIP_GENESIS=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

FULL_IMAGE="${IMAGE}:${IMAGE_TAG}"

node_docker() { local n="$1"; shift; docker exec "$n" docker "$@"; }
node_exec()   { local n="$1"; shift; docker exec "$n" sh -c "$*"; }
step()        { echo ""; echo "═══ $1 ═══"; }
FAILURES=0
check_pass() { echo "  ✅ $1"; }
check_fail() { echo "  ❌ $1"; FAILURES=$((FAILURES + 1)); }
START_TIME=$(date +%s)

# ── Pull ─────────────────────────────────────────────────────────────────
step "Pull check"
for node in "${NODES[@]}"; do
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "$GITHUB_TOKEN" | docker exec -i "$node" docker login ghcr.io -u ottobot-ai --password-stdin 2>/dev/null || true
  fi
  node_docker "$node" pull "$FULL_IMAGE" 2>&1 | tail -1
  check_pass "$node"
done

# ── Stop ─────────────────────────────────────────────────────────────────
step "Stop existing"
CONTAINERS="gl0 gl1 ml0 cl1 dl1 promtail node-exporter"
for node in "${NODES[@]}"; do
  for c in $CONTAINERS; do node_docker "$node" update --restart no "$c" 2>/dev/null || true; done
  node_exec "$node" "timeout 60 sh -c 'cd /opt/ottochain && docker compose down 2>/dev/null'" || true
  node_exec "$node" "timeout 60 docker rm -f $CONTAINERS 2>/dev/null" || true
  check_pass "$node"
done

# ── Wipe ─────────────────────────────────────────────────────────────────
if [ "$WIPE" = "true" ]; then
  step "Wipe state"
  for node in "${NODES[@]}"; do
    node_exec "$node" "rm -rf /opt/ottochain/{gl0,gl1,ml0,cl1,dl1}-{data,logs}"
    node_exec "$node" "mkdir -p /opt/ottochain/{gl0,ml0,dl1}-{data,logs}"
    check_pass "$node"
  done
fi

# ── Genesis ──────────────────────────────────────────────────────────────
# Strategy: create a temporary "toolbox" container that persists, copy tools in,
# run commands, copy artifacts out. Avoids DinD volume mount issues entirely.
if [ "$SKIP_GENESIS" = "false" ]; then
  step "Genesis setup"
  TOOLS_DIR="/tmp/ottochain-test-tools"
  mkdir -p "$TOOLS_DIR"
  for jar in cl-wallet.jar cl-keytool.jar; do
    if [ ! -f "$TOOLS_DIR/$jar" ]; then
      echo "  Downloading $jar..."
      curl -sL -o "$TOOLS_DIR/$jar" "https://github.com/Constellation-Labs/tessellation/releases/download/v${TESS_VERSION}/$jar"
    fi
  done

  # Create a persistent toolbox container on node1
  node_docker "${NODES[0]}" rm -f toolbox 2>/dev/null || true
  node_docker "${NODES[0]}" create --name toolbox \
    -e CL_KEYSTORE=/work/key.p12 -e CL_KEYALIAS=alias -e CL_PASSWORD=testpass \
    --entrypoint sleep "$FULL_IMAGE" infinity >/dev/null
  node_docker "${NODES[0]}" start toolbox >/dev/null

  # Copy tools into DinD node, then into toolbox container
  # NOTE: /tmp is tmpfs in Alpine DinD — use /opt/ instead
  docker cp "$TOOLS_DIR/cl-keytool.jar" "test-node1:/opt/cl-keytool.jar"
  docker cp "$TOOLS_DIR/cl-wallet.jar" "test-node1:/opt/cl-wallet.jar"
  docker exec test-node1 docker exec toolbox mkdir -p /work
  docker exec test-node1 docker cp /opt/cl-keytool.jar toolbox:/work/cl-keytool.jar
  docker exec test-node1 docker cp /opt/cl-wallet.jar toolbox:/work/cl-wallet.jar

  # Generate keystore
  echo "  Generating keystore..."
  docker exec test-node1 docker exec \
    -e CL_KEYSTORE=/work/key.p12 -e CL_KEYALIAS=alias -e CL_PASSWORD=testpass \
    toolbox java -jar /work/cl-keytool.jar generate 2>&1
  check_pass "Keystore"

  # Extract peer ID
  PEER_ID=$(docker exec test-node1 docker exec \
    -e CL_KEYSTORE=/work/key.p12 -e CL_KEYALIAS=alias -e CL_PASSWORD=testpass \
    toolbox java -jar /work/cl-wallet.jar show-id 2>/dev/null || echo "")
  check_pass "Peer ID: ${PEER_ID:0:32}..."

  # Extract wallet
  WALLET=$(docker exec test-node1 docker exec \
    -e CL_KEYSTORE=/work/key.p12 -e CL_KEYALIAS=alias -e CL_PASSWORD=testpass \
    toolbox java -jar /work/cl-wallet.jar show-address 2>&1 | grep -oP 'DAG[a-zA-Z0-9]+' | head -1 || echo "")
  echo "  Wallet: $WALLET"

  # Create genesis CSV in toolbox
  docker exec test-node1 docker exec toolbox sh -c "echo '${WALLET},1000000000000000' > /work/genesis.csv"

  # Copy keystore + genesis CSV to DinD node filesystem
  docker exec test-node1 mkdir -p /opt/ottochain/keys /opt/ottochain/genesis
  docker exec test-node1 docker cp toolbox:/work/key.p12 /opt/ottochain/keys/key.p12
  docker exec test-node1 docker cp toolbox:/work/genesis.csv /opt/ottochain/genesis/genesis.csv

  step "GL0 genesis"
  # Run GL0 in genesis mode — uses --network host so it's reachable at 127.0.0.1:9000
  node_docker "${NODES[0]}" run -d --name gl0-genesis --network host \
    -v /opt/ottochain/keys:/ottochain/keys:ro \
    -v /opt/ottochain/genesis:/ottochain/genesis:ro \
    -e LAYER=gl0 -e IS_INITIAL=true -e CL_APP_ENV=dev -e CL_EXTERNAL_IP=127.0.0.1 \
    -e CL_COLLATERAL=0 -e CL_KEYSTORE=/ottochain/keys/key.p12 -e CL_KEYALIAS=alias \
    -e CL_PASSWORD=testpass -e JAVA_OPTS='-Xmx1g -Xms512m' \
    "$FULL_IMAGE" >/dev/null

  echo "  Waiting for GL0 Ready..."
  GL0_READY=false
  for i in $(seq 1 60); do
    state=$(node_exec "${NODES[0]}" "wget -qO- http://127.0.0.1:9000/node/info 2>/dev/null" | grep -o '"state":"[^"]*"' | cut -d'"' -f4 || echo "")
    if [ "$state" = "Ready" ]; then check_pass "GL0 Ready (${i}x5s)"; GL0_READY=true; break; fi
    sleep 5
  done
  if [ "$GL0_READY" = "false" ]; then
    check_fail "GL0 timeout — cannot proceed to ML0 genesis without a ready GL0"
    exit 1
  fi

  step "ML0 genesis snapshot"
  # Run ML0 create-genesis against the running GL0
  node_docker "${NODES[0]}" run --rm --network host --entrypoint '' \
    -v /opt/ottochain/keys:/ottochain/keys:ro \
    -v /opt/ottochain/genesis:/ottochain/genesis \
    -w /ottochain/genesis \
    -e CL_KEYSTORE=/ottochain/keys/key.p12 -e CL_KEYALIAS=alias -e CL_PASSWORD=testpass \
    -e CL_GLOBAL_L0_PEER_ID=${PEER_ID} \
    -e CL_GLOBAL_L0_PEER_HOST=127.0.0.1 -e CL_GLOBAL_L0_PEER_PORT=9000 \
    -e CL_GLOBAL_L0_PEER_HTTP_HOST=127.0.0.1 -e CL_GLOBAL_L0_PEER_HTTP_PORT=9000 \
    -e CL_PUBLIC_HTTP_PORT=9200 -e CL_P2P_HTTP_PORT=9201 -e CL_CLI_HTTP_PORT=9202 \
    -e CL_COLLATERAL=0 -e CL_APP_ENV=dev -e CL_EXTERNAL_IP=127.0.0.1 \
    "$FULL_IMAGE" java -jar /ottochain/jars/ml0.jar create-genesis /ottochain/genesis/genesis.csv 2>&1 | tail -3

  TOKEN_ID=$(node_exec "${NODES[0]}" "cat /opt/ottochain/genesis/genesis.address 2>/dev/null" || echo "")
  if [ -n "$TOKEN_ID" ]; then
    check_pass "TOKEN_ID=$TOKEN_ID"
  else
    check_fail "ML0 genesis failed"
  fi

  node_docker "${NODES[0]}" rm -f gl0-genesis toolbox 2>/dev/null || true
else
  # --skip-genesis: require PEER_ID and TOKEN_ID to be set in the environment.
  # Defaulting to "mock" silently produces a broken deploy that fails at ML0 join time.
  if [ -z "${PEER_ID:-}" ] || [ -z "${TOKEN_ID:-}" ]; then
    echo "❌ --skip-genesis requires PEER_ID and TOKEN_ID to be set in the environment."
    echo "   Run without --skip-genesis on first use, or export the values from a prior run:"
    echo "     export PEER_ID=<peer-id>"
    echo "     export TOKEN_ID=<token-id>"
    exit 1
  fi
fi

# ── Deploy compose + .env ────────────────────────────────────────────────
step "Deploy compose + .env"
for i in 0 1 2; do
  node="${NODES[$i]}"
  node_ip="${NODE_IPS[$i]}"
  IS_INITIAL=""; [ "$i" = "0" ] && IS_INITIAL="true"

  # Copy compose file + patch for DinD: use host networking so containers
  # can reach other DinD nodes via the outer Docker network (172.28.0.x)
  cp "${REPO_ROOT}/compose/metagraph-node.yml" /tmp/metagraph-node-dind.yml
  # Remove ports: sections and add network_mode: host to each service
  python3 -c "
import yaml, sys
with open('/tmp/metagraph-node-dind.yml') as f:
    d = yaml.safe_load(f)
for svc in d.get('services', {}).values():
    svc.pop('ports', None)
    svc['network_mode'] = 'host'
with open('/tmp/metagraph-node-dind.yml', 'w') as f:
    yaml.dump(d, f, default_flow_style=False)
" 2>/dev/null || {
    # Fallback if PyYAML not available: sed-based patch
    sed -i '/^    ports:/,/^    [^ ]/{ /^    ports:/d; /^      - /d; }' /tmp/metagraph-node-dind.yml
    sed -i 's/^  \([a-z0-9]*\):$/  \1:\n    network_mode: host/' /tmp/metagraph-node-dind.yml
  }
  docker cp /tmp/metagraph-node-dind.yml "${node}:/opt/ottochain/docker-compose.yml"
  node_exec "$node" "mkdir -p /opt/ottochain/keys /opt/ottochain/genesis /opt/ottochain/{gl0,ml0,dl1}-{data,logs}"

  # Copy keys/genesis from node1 to others
  if [ "$i" -gt 0 ]; then
    for f in keys/key.p12 genesis/genesis.address genesis/genesis.snapshot genesis/genesis.csv; do
      docker exec "${NODES[0]}" cat "/opt/ottochain/$f" 2>/dev/null | docker exec -i "$node" sh -c "cat > /opt/ottochain/$f" 2>/dev/null || true
    done
  fi

  # Write .env
  # With host networking, containers share the DinD host's network namespace
  # so NODE1_IP is the outer Docker network IP (reachable from all DinD nodes)
  docker exec "$node" sh -c "cat > /opt/ottochain/.env << 'ENVEOF'
IMAGE=${FULL_IMAGE}
EXTERNAL_IP=${node_ip}
NODE1_IP=${NODE_IPS[0]}
IS_INITIAL=${IS_INITIAL}
KEYS_DIR=/opt/ottochain/keys
CL_PASSWORD=testpass
GL0_PEER_ID=${PEER_ID}
ML0_PEER_ID=${PEER_ID}
TOKEN_ID=${TOKEN_ID}
LOKI_URL=http://localhost:3100
GL0_JAVA_OPTS=-Xmx1g -Xms512m
ML0_JAVA_OPTS=-Xmx1g -Xms512m
DL1_JAVA_OPTS=-Xmx1g -Xms512m
CL1_JAVA_OPTS=-Xmx512m -Xms256m
ENVEOF"

  # Minimal logback
  docker exec "$node" sh -c 'cat > /opt/ottochain/logback.xml << "XML"
<configuration>
  <appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
    <encoder><pattern>%d{HH:mm:ss} %-5level %logger{36} - %msg%n</pattern></encoder>
  </appender>
  <root level="INFO"><appender-ref ref="STDOUT" /></root>
</configuration>
XML'

  check_pass "$node (IS_INITIAL=${IS_INITIAL:-false})"
done

# ── Helper: wait for layer Ready ─────────────────────────────────────────
wait_ready() {
  local node="$1" port="$2" name="$3" max="${4:-90}"
  for i in $(seq 1 "$max"); do
    state=$(node_exec "$node" "wget -qO- http://127.0.0.1:${port}/node/info 2>/dev/null" | grep -o '"state":"[^"]*"' | cut -d'"' -f4 || echo "")
    if [ "$state" = "Ready" ]; then check_pass "$name Ready (${i}x5s)"; return 0; fi
    # Check for crash
    local st=$(node_docker "$node" ps -a --format '{{.Names}} {{.Status}}' 2>/dev/null | grep "${name,,}" || echo "")
    if echo "$st" | grep -qi "Exited\|Restarting"; then
      echo "  Container status: $st"
      node_docker "$node" logs "${name,,}" --tail 5 2>&1
      check_fail "$name crashed"; return 1
    fi
    sleep 5
  done
  check_fail "$name timeout"; return 1
}

# ── Helper: join cluster ─────────────────────────────────────────────────
join_cluster() {
  local cli_port="$1" p2p_port="$2" name="$3"
  for i in 1 2; do
    local node="${NODES[$i]}"
    for j in $(seq 1 30); do
      state=$(node_exec "$node" "wget -qO- http://127.0.0.1:${cli_port}/node/info 2>/dev/null" | grep -o '"state":"[^"]*"' | cut -d'"' -f4 || echo "")
      { [ "$state" = "ReadyToJoin" ] || [ "$state" = "Ready" ]; } && break
      sleep 5
    done
    node_exec "$node" "wget -qO- --post-data='{\"id\":\"${PEER_ID}\",\"ip\":\"${NODE_IPS[0]}\",\"p2pPort\":${p2p_port}}' --header='Content-Type: application/json' 'http://127.0.0.1:${cli_port}/cluster/join'" 2>/dev/null || true
    check_pass "$node joined $name"
  done
}

# ── GL0 ──────────────────────────────────────────────────────────────────
step "Start GL0"
for node in "${NODES[@]}"; do
  node_exec "$node" "cd /opt/ottochain && docker compose up -d gl0" 2>&1 | grep -v "^$"
done
wait_ready "${NODES[0]}" 9000 GL0

step "Join GL0"
join_cluster 9002 9001 GL0

# ── ML0 ──────────────────────────────────────────────────────────────────
step "Start ML0"
for node in "${NODES[@]}"; do
  node_exec "$node" "cd /opt/ottochain && docker compose up -d ml0" 2>&1 | grep -v "^$"
done
if wait_ready "${NODES[0]}" 9200 ML0; then
  step "Join ML0"
  join_cluster 9202 9201 ML0
fi

# ── DL1 ──────────────────────────────────────────────────────────────────
step "Start DL1"
for node in "${NODES[@]}"; do
  node_exec "$node" "cd /opt/ottochain && docker compose up -d dl1" 2>&1 | grep -v "^$"
done
if wait_ready "${NODES[0]}" 9400 DL1; then
  step "Join DL1"
  join_cluster 9402 9401 DL1
fi

# ── Summary ──────────────────────────────────────────────────────────────
step "Results"
ELAPSED=$(( $(date +%s) - START_TIME ))
for node in "${NODES[@]}"; do
  echo "  $node:"
  for lp in "9000:GL0" "9200:ML0" "9400:DL1"; do
    port="${lp%%:*}"; layer="${lp##*:}"
    state=$(node_exec "$node" "wget -qO- http://127.0.0.1:${port}/node/info 2>/dev/null" | grep -o '"state":"[^"]*"' | cut -d'"' -f4 || echo "DOWN")
    icon="✅"; [ "$state" != "Ready" ] && icon="❌"
    echo "    $icon $layer: $state"
  done
done
echo ""
echo "  Time: ${ELAPSED}s | Failures: $FAILURES"
[ "$FAILURES" -gt 0 ] && { echo "  ❌ FAILED"; exit 1; } || { echo "  ✅ ALL PASSED"; exit 0; }
