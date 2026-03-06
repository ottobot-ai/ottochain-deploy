# Local Deploy Test Harness

Tests the metagraph deploy workflow locally using Docker-in-Docker containers,
without touching the real Hetzner cluster or burning GitHub Actions minutes.

## Architecture

```
┌─────────────────────────────────────────────┐
│  Host (Euler / CI runner)                    │
│                                              │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐     │
│  │ test-    │  │ test-    │  │ test-    │     │
│  │ node1    │  │ node2    │  │ node3    │     │
│  │ (DinD)   │  │ (DinD)   │  │ (DinD)   │     │
│  │          │  │          │  │          │     │
│  │ ┌──────┐│  │ ┌──────┐│  │ ┌──────┐│     │
│  │ │ gl0  ││  │ │ gl0  ││  │ │ gl0  ││     │
│  │ │ ml0  ││  │ │ ml0  ││  │ │ ml0  ││     │
│  │ │ dl1  ││  │ │ dl1  ││  │ │ dl1  ││     │
│  │ └──────┘│  │ └──────┘│  │ └──────┘│     │
│  └─────────┘  └─────────┘  └─────────┘     │
│    172.28.0.11  172.28.0.12  172.28.0.13    │
└─────────────────────────────────────────────┘
```

Each "node" is a Docker-in-Docker container that runs its own Docker daemon.
Metagraph containers (GL0, ML0, DL1) run _inside_ each DinD node, just like
on the real Hetzner servers.

## Usage

```bash
cd test/local

# Start the DinD nodes
docker compose up -d

# Wait for healthy
docker compose ps

# Run the deploy test (pulls image, runs genesis, deploys all layers)
export GITHUB_TOKEN=ghp_...   # needed to pull from GHCR
./run-deploy-test.sh

# Specific image tag
./run-deploy-test.sh --image-tag 0.7.10

# Skip genesis (reuse existing state)
./run-deploy-test.sh --no-wipe --skip-genesis

# Clean up
docker compose down -v
```

## What It Tests

1. **Container stop/remove** with timeouts (the fix from PR #165)
2. **Genesis flow** — GL0 genesis → ML0 snapshot creation → token ID
3. **Entrypoint args** — catches issues like `--l0-token-identifier` on ML0
4. **Layer startup sequence** — GL0 → ML0 → DL1
5. **Cluster join** — all 3 nodes join each layer's cluster
6. **Health checks** — all nodes reach Ready state

## Requirements

- Docker with compose v2
- ~4GB RAM (3 DinD nodes + 3 layers × 512MB-1GB JVM each)
- GHCR access (GITHUB_TOKEN) or pre-pulled metagraph image

## Limitations

- Uses the same keystore for all 3 nodes (real deploy has unique keys per node)
- No Loki/Prometheus/Promtail (infrastructure services skipped)
- No SSL or domain names
- Network is a flat bridge, not simulating private/public IP split
