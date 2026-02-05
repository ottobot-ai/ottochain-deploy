# OttoChain Docker Deployment

This directory contains Docker-based deployment for OttoChain metagraph.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         3-Node Cluster                          │
├─────────────────┬─────────────────┬─────────────────────────────┤
│     Node 1      │     Node 2      │          Node 3             │
│  (Genesis)      │  (Validator)    │        (Validator)          │
├─────────────────┼─────────────────┼─────────────────────────────┤
│ GL0 :9000-9002  │ GL0 :9000-9002  │ GL0 :9000-9002              │
│ GL1 :9100-9102  │ GL1 :9100-9102  │ GL1 :9100-9102              │
│ ML0 :9200-9202  │ ML0 :9200-9202  │ ML0 :9200-9202              │
│ CL1 :9300-9302  │ CL1 :9300-9302  │ CL1 :9300-9302              │
│ DL1 :9400-9402  │ DL1 :9400-9402  │ DL1 :9400-9402              │
└─────────────────┴─────────────────┴─────────────────────────────┘
```

Each node runs all 5 layers with the same key. Layers peer across machines.

## Quick Start

### 1. Build JARs (locally or in CI)

```bash
# Build tessellation JARs
cd tessellation
sbt dagL0/assembly dagL1/assembly

# Build metagraph JARs
cd ottochain
sbt assembly

# Collect JARs
mkdir -p jars
cp tessellation/modules/dag-l0/target/scala-2.13/dag-l0-assembly-*.jar jars/dag-l0.jar
cp tessellation/modules/dag-l1/target/scala-2.13/dag-l1-assembly-*.jar jars/dag-l1.jar
cp ottochain/modules/l0/target/scala-2.13/ottochain-l0-assembly-*.jar jars/metagraph-l0.jar
cp ottochain/modules/l1/target/scala-2.13/ottochain-l1-assembly-*.jar jars/currency-l1.jar
cp ottochain/modules/data-l1/target/scala-2.13/ottochain-data-l1-assembly-*.jar jars/data-l1.jar
```

### 2. Deploy to nodes

```bash
# Copy files to each node
for node in node1 node2 node3; do
  scp -r docker/metagraph/docker-compose.yml $node:/opt/ottochain/
  scp jars/*.jar $node:/opt/ottochain/jars/
done
```

### 3. Start genesis node (node1)

```bash
ssh node1
cd /opt/ottochain

# Create .env
cat > .env << EOF
CL_PASSWORD=your-keystore-password
NODE_IP=5.78.90.207
GL0_PEER_ID=$(java -jar jars/dag-l0.jar show-id)
EOF

# Start genesis
docker compose --profile genesis up -d
```

### 4. Start validator nodes (node2, node3)

```bash
ssh node2
cd /opt/ottochain

# Create .env with genesis node info
cat > .env << EOF
CL_PASSWORD=your-keystore-password
NODE_IP=5.78.113.25
GENESIS_IP=5.78.90.207
GL0_PEER_ID=<genesis-peer-id>
GL1_PEER_ID=<genesis-peer-id>
ML0_PEER_ID=<genesis-peer-id>
TOKEN_ID=<from-ml0-node-info>
EOF

# Start validator
docker compose --profile validator up -d
```

## Profiles

The compose file uses Docker Compose profiles:

- `genesis` - For the first node (runs genesis commands)
- `validator` - For joining nodes (runs validator commands)

## Environment Variables

| Variable | Description |
|----------|-------------|
| `CL_PASSWORD` | Keystore password |
| `NODE_IP` | This node's public IP |
| `GENESIS_IP` | Genesis node's IP (for validators) |
| `GL0_PEER_ID` | Genesis GL0 peer ID |
| `GL1_PEER_ID` | Genesis GL1 peer ID |
| `ML0_PEER_ID` | Genesis ML0 peer ID |
| `TOKEN_ID` | Metagraph token ID (from ML0) |

## CI/CD

Push to `release/scratch` branch triggers full deployment:

1. Builds JARs from `ottochain` and `tessellation` repos
2. Deploys JARs to all nodes
3. Starts cluster in sequence (GL0 → GL1 → ML0 → CL1 → DL1)
4. Deploys services (indexer, explorer, monitor)
5. Runs health checks

Manual trigger available via GitHub Actions with options:
- `wipe_state`: Reset all state (genesis from scratch)
- `skip_build`: Use existing JARs

## Troubleshooting

### Check container logs
```bash
docker logs gl0
docker logs ml0
docker logs dl1
```

### Check cluster status
```bash
curl http://localhost:9000/cluster/info | jq length  # GL0
curl http://localhost:9200/cluster/info | jq length  # ML0
curl http://localhost:9400/cluster/info | jq length  # DL1
```

### Restart a layer
```bash
docker compose restart ml0
```

### Full reset
```bash
docker compose down
rm -rf data/* logs/*
docker compose --profile genesis up -d
```
