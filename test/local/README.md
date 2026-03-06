# Local OttoChain Cluster

Full-stack local cluster for development, testing, and demos. Runs 17 containers
on a shared Docker network — no DinD, no nesting, no surprises.

## Architecture

```
Docker network: ottochain-local (172.30.0.0/24)

┌──────────── Metagraph (9 nodes) ────────────┐
│  GL0-1 (.11)   GL0-2 (.12)   GL0-3 (.13)   │  Global L0
│  ML0-1 (.21)   ML0-2 (.22)   ML0-3 (.23)   │  Metagraph L0
│  DL1-1 (.31)   DL1-2 (.32)   DL1-3 (.33)   │  Data L1
└─────────────────────────────────────────────┘

┌──────────── Services (8 containers) ────────┐
│  Postgres (.50)    Redis (.51)              │
│  Gateway (.52)     Bridge (.53)             │
│  Indexer (.54)     Explorer (.55)           │
│  Traffic-Gen (.56) Monitor (.57)            │
└─────────────────────────────────────────────┘
```

## Quick Start

```bash
cd test/local

# Full setup (genesis, keys, cluster join, services)
./setup.sh

# ~8 minutes later:
#   Explorer:  http://localhost:8080
#   Gateway:   http://localhost:4000/graphql
#   Bridge:    http://localhost:3030
#   Monitor:   http://localhost:3032

# Restart without regenerating genesis
./setup.sh --skip-genesis

# Use a different metagraph image
./setup.sh --image-tag 0.8.0

# Tear down
docker compose down -v
```

> **Remote access or WSL2?** If your Docker host is not `localhost` (e.g. running on a remote VM, WSL2, or another machine), set `HOST_IP` so the explorer can reach the API:
> ```bash
> export HOST_IP=192.168.1.100   # your Docker host IP
> ./setup.sh
> ```
> Without `HOST_IP`, the explorer defaults to `localhost` (works for local Docker Desktop).

## What `setup.sh` Does

1. Downloads `cl-keytool.jar` + `cl-wallet.jar` from tessellation releases
2. Generates PKCS12 keystores for 3 nodes (unique keys per node)
3. Extracts peer ID and wallet address from node1's keystore
4. Runs GL0 genesis → creates ML0 genesis snapshot → gets token ID
5. Writes `.env` with all derived values
6. Starts all 17 containers via `docker compose up`
7. Joins GL0, ML0, DL1 clusters (node1 = genesis, nodes 2+3 join)
8. Prints cluster status and access URLs

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | All 17 container definitions, networks, static IPs |
| `setup.sh` | Automated genesis + cluster bootstrap |
| `entrypoint-fixed.sh` | Patched metagraph entrypoint (workaround for image ≤0.7.9 startup bug — remove once >0.7.9 is released) |
| `compose-override.yml` | **DinD-only override** — applies only if you're running Docker-in-Docker (see PR #166). Not needed for the plain Docker setup this PR introduces. |
| `data/` | Generated at runtime: keys, genesis, tools (gitignored) |
| `.env` | Generated at runtime: peer ID, token ID, image refs |

## Checking Health

```bash
# All layers
for lp in "gl0:9000" "ml0:9200" "dl1:9400"; do
  l="${lp%%:*}"; p="${lp##*:}"
  for n in 1 2 3; do
    state=$(docker exec "${l}-${n}" wget -qO- "http://127.0.0.1:${p}/node/info" 2>/dev/null \
      | grep -o '"state":"[^"]*"' | cut -d'"' -f4 || echo "DOWN")
    echo "${l}-${n}: $state"
  done
done

# GraphQL
curl -s localhost:4000/graphql -H "Content-Type: application/json" \
  -d '{"query":"{networkStats{totalAgents totalFibers lastSnapshotOrdinal}}"}'
```

## Debugging

```bash
docker logs ml0-1 --tail 50     # Metagraph logs
docker logs gateway --tail 50   # Service logs
docker exec -it bridge sh       # Shell into container
docker exec gateway env | sort  # Check env vars
docker restart indexer           # Restart one service
```

## Hot-Deploying Changes

### Services (bridge, gateway, indexer, etc.)

```bash
cd ~/repos/ottochain-services
docker build -t ghcr.io/ottobot-ai/ottochain-services:latest .
docker compose -f ~/repos/ottochain-deploy/test/local/docker-compose.yml up -d gateway bridge indexer
```

### Explorer

```bash
cd ~/repos/ottochain-explorer && pnpm build
docker exec explorer sh -c 'rm -rf /usr/share/nginx/html/assets/*'
docker cp dist/. explorer:/usr/share/nginx/html/
# Hard refresh browser
```

## Known Issues

| Issue | Cause | Workaround |
|-------|-------|------------|
| ML0 crash: `Unexpected option` | Image 0.7.9 entrypoint bug | `entrypoint-fixed.sh` mounted in compose (remove when image >0.7.9) |
| Explorer can't reach API | `HOST_IP` not set for remote/WSL2 host | `export HOST_IP=<your-docker-host-ip>` before running setup |
| Can't curl metagraph from host | Ports not mapped to host | Use `docker exec <c> wget -qO-` |
| Explorer shows no data | Browser cached empty state | Hard refresh (Ctrl+Shift+R) |
| Traffic gen `fetch failed` | `INDEXER_URL` not read | Set in compose env (PR #216) |

## Requirements

- Docker with compose v2
- ~6GB RAM (9 JVMs × ~512MB + services)
- GHCR access (`docker login ghcr.io`) or pre-pulled images
- `curl`, `grep`, `sed` (used by setup.sh)
