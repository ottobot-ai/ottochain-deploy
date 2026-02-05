#!/bin/bash
set -e

SSH_KEY="$HOME/.ssh/hetzner_ottobot"
GENESIS_IP="5.78.90.207"

# Node to join (pass as argument)
NODE_NAME="${1:-node2}"

declare -A NODES=(
  ["node2"]="5.78.113.25"
  ["node3"]="5.78.107.77"
)

if [ -z "${NODES[$NODE_NAME]}" ]; then
  echo "Usage: $0 <node2|node3>"
  exit 1
fi

NODE_IP="${NODES[$NODE_NAME]}"

echo "=== Joining $NODE_NAME ($NODE_IP) to cluster ==="

ssh -i $SSH_KEY root@$NODE_IP "
cd /opt/ottochain

# Stop any running containers
docker compose down 2>/dev/null || true

# Create join override with genesis node as peer
cat > docker-compose.override.yml << EOF
version: '3.8'
services:
  gl0:
    environment:
      - CL_L0_PEER_HTTP_HOST=$GENESIS_IP
      - CL_L0_PEER_HTTP_PORT=9000
  ml0:
    environment:
      - CL_GLOBAL_L0_PEER_HTTP_HOST=$GENESIS_IP
      - CL_GLOBAL_L0_PEER_HTTP_PORT=9000
      - CL_L0_PEER_HTTP_HOST=$GENESIS_IP
      - CL_L0_PEER_HTTP_PORT=9200
  dl1:
    environment:
      - CL_GLOBAL_L0_PEER_HTTP_HOST=$GENESIS_IP
      - CL_GLOBAL_L0_PEER_HTTP_PORT=9000
      - CL_L0_PEER_HTTP_HOST=$GENESIS_IP
      - CL_L0_PEER_HTTP_PORT=9200
EOF

# Start all services
echo 'Starting GL0...'
docker compose up -d gl0

echo 'Waiting for GL0...'
for i in {1..60}; do
  if curl -sf http://localhost:9000/node/info > /dev/null 2>&1; then
    echo 'GL0 is ready!'
    break
  fi
  echo -n '.'
  sleep 2
done

echo ''
curl -s http://localhost:9000/node/info | jq . 2>/dev/null || echo 'GL0 not responding'

echo 'Starting ML0...'
docker compose up -d ml0

echo 'Waiting for ML0...'
for i in {1..60}; do
  if curl -sf http://localhost:9200/node/info > /dev/null 2>&1; then
    echo 'ML0 is ready!'
    break
  fi
  echo -n '.'
  sleep 2
done

echo ''
curl -s http://localhost:9200/node/info | jq . 2>/dev/null || echo 'ML0 not responding'

echo 'Starting DL1...'
docker compose up -d dl1

echo 'Waiting for DL1...'
for i in {1..60}; do
  if curl -sf http://localhost:9400/node/info > /dev/null 2>&1; then
    echo 'DL1 is ready!'
    break
  fi
  echo -n '.'
  sleep 2
done

echo ''
curl -s http://localhost:9400/node/info | jq . 2>/dev/null || echo 'DL1 not responding'

echo ''
echo 'Node status:'
docker compose ps
"

echo ""
echo "=== $NODE_NAME joined cluster ==="
echo "GL0: http://$NODE_IP:9000"
echo "ML0: http://$NODE_IP:9200"
echo "DL1: http://$NODE_IP:9400"
