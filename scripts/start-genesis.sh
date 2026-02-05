#!/bin/bash
set -e

SSH_KEY="$HOME/.ssh/hetzner_ottobot"
GENESIS_IP="5.78.90.207"

echo "=== Starting Genesis Node (node1: $GENESIS_IP) ==="

# Create genesis snapshot
ssh -i $SSH_KEY root@$GENESIS_IP "
cd /opt/ottochain

# Stop any running containers
docker compose down 2>/dev/null || true

# Create genesis override
cat > docker-compose.override.yml << 'EOF'
version: '3.8'
services:
  gl0:
    environment:
      - GENESIS_MODE=true
EOF

# Start GL0 in genesis mode
echo 'Starting GL0 in genesis mode...'
docker compose up -d gl0

# Wait for GL0 to be healthy
echo 'Waiting for GL0...'
for i in {1..60}; do
  if curl -sf http://localhost:9000/node/info > /dev/null 2>&1; then
    echo 'GL0 is ready!'
    break
  fi
  echo -n '.'
  sleep 2
done

# Get GL0 info
echo ''
curl -s http://localhost:9000/node/info | jq .

# Remove genesis override and restart in validator mode
rm docker-compose.override.yml

echo 'Restarting GL0 in validator mode...'
docker compose up -d gl0

sleep 5

# Start ML0
echo 'Starting ML0...'
docker compose up -d ml0

# Wait for ML0
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
curl -s http://localhost:9200/node/info | jq .

# Start DL1
echo 'Starting DL1...'
docker compose up -d dl1

# Wait for DL1
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
curl -s http://localhost:9400/node/info | jq .

echo ''
echo 'All layers started on genesis node!'
docker compose ps
"

echo ""
echo "=== Genesis node started ==="
echo "GL0: http://$GENESIS_IP:9000"
echo "ML0: http://$GENESIS_IP:9200"
echo "DL1: http://$GENESIS_IP:9400"
