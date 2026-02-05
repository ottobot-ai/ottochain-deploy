#!/bin/bash
set -e

SSH_KEY="$HOME/.ssh/hetzner_ottobot"
DEPLOY_DIR="$HOME/.openclaw/workspace/ottochain-deploy"

declare -A NODES=(
  ["node1"]="5.78.90.207"
  ["node2"]="5.78.113.25"
  ["node3"]="5.78.107.77"
)

echo "=== Setting up OttoChain nodes ==="

for node in "${!NODES[@]}"; do
  ip="${NODES[$node]}"
  echo ""
  echo "=== Setting up $node ($ip) ==="
  
  # Create directories
  ssh -i $SSH_KEY root@$ip "mkdir -p /opt/ottochain/{keys,data}"
  
  # Copy Docker files
  echo "Copying Docker files..."
  scp -i $SSH_KEY $DEPLOY_DIR/docker/Dockerfile root@$ip:/opt/ottochain/
  scp -i $SSH_KEY $DEPLOY_DIR/docker/entrypoint.sh root@$ip:/opt/ottochain/
  scp -i $SSH_KEY $DEPLOY_DIR/docker/docker-compose.yml root@$ip:/opt/ottochain/
  
  # Make entrypoint executable
  ssh -i $SSH_KEY root@$ip "chmod +x /opt/ottochain/entrypoint.sh"
  
  # Generate node key if not exists
  echo "Checking/generating node key..."
  ssh -i $SSH_KEY root@$ip "
    if [ ! -f /opt/ottochain/keys/key.p12 ]; then
      cd /opt/ottochain
      java -jar jars/keytool.jar generate --alias alias --password password --output keys/key.p12
      echo 'Generated new key for $node'
    else
      echo 'Key already exists for $node'
    fi
  "
  
  # Get node ID
  NODE_ID=$(ssh -i $SSH_KEY root@$ip "java -jar /opt/ottochain/jars/keytool.jar show --alias alias --password password --keystore /opt/ottochain/keys/key.p12 2>/dev/null | grep 'Id:' | awk '{print \$2}' || echo 'unknown'")
  echo "$node ID: $NODE_ID"
  
  # Build Docker image
  echo "Building Docker image on $node..."
  ssh -i $SSH_KEY root@$ip "cd /opt/ottochain && docker build -t ottochain/node:latest ."
  
  echo "Done: $node"
done

echo ""
echo "=== All nodes set up ==="
echo "Next: Run start-genesis.sh on node1"
