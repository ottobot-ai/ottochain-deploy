#!/bin/bash
set -e

BRIDGE_IP="5.78.121.248"
SSH_KEY="$HOME/.ssh/hetzner_ottobot"
REMOTE_DIR="/opt/ottochain-services"
SERVICES_SRC="$HOME/.openclaw/workspace/ottochain-services"

echo "=== Deploying OttoChain Services to $BRIDGE_IP ==="

# Create remote directory
ssh -i $SSH_KEY root@$BRIDGE_IP "mkdir -p $REMOTE_DIR/app"

# Sync services source (excluding node_modules, .git)
echo "Syncing services source..."
rsync -avz --progress \
  --exclude 'node_modules' \
  --exclude '.git' \
  --exclude 'dist' \
  --exclude 'sdk/node_modules' \
  -e "ssh -i $SSH_KEY" \
  $SERVICES_SRC/ root@$BRIDGE_IP:$REMOTE_DIR/app/

# Copy docker-compose.yml
echo "Copying Docker compose files..."
scp -i $SSH_KEY docker-compose.yml root@$BRIDGE_IP:$REMOTE_DIR/

# Copy Dockerfile
scp -i $SSH_KEY app/Dockerfile root@$BRIDGE_IP:$REMOTE_DIR/app/

echo "=== Starting services ==="
ssh -i $SSH_KEY root@$BRIDGE_IP "cd $REMOTE_DIR && docker compose up -d --build"

echo "=== Checking status ==="
ssh -i $SSH_KEY root@$BRIDGE_IP "cd $REMOTE_DIR && docker compose ps"

echo "Done! Services available at:"
echo "  Bridge:   http://$BRIDGE_IP:3030"
echo "  Indexer:  http://$BRIDGE_IP:3031"
echo "  Gateway:  http://$BRIDGE_IP:4000"
