# OttoChain Cluster Architecture

## Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SERVICES NODE (5.78.121.248)                 │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │              Single Docker Compose Stack                     │    │
│  │              /opt/ottochain-services/                        │    │
│  │                                                              │    │
│  │  ┌─── Application Services ──────────────────────────────┐  │    │
│  │  │  gateway (:4000)     GraphQL API                      │  │    │
│  │  │  bridge  (:3030)     Metagraph relay, key management  │  │    │
│  │  │  indexer (:3031)     ML0 snapshot indexer → Postgres   │  │    │
│  │  │  status  (:3032)     Polls nodes, caches in Redis,     │  │    │
│  │  │                      serves /api/status, app alerts    │  │    │
│  │  │  traffic-gen         Load generator (bridge → DL1)     │  │    │
│  │  │  explorer (:8081)    Block explorer frontend           │  │    │
│  │  └───────────────────────────────────────────────────────┘  │    │
│  │                                                              │    │
│  │  ┌─── Data Stores ──────────────────────────────────────┐   │    │
│  │  │  postgres (:5432)    Indexed chain data (localhost)    │  │    │
│  │  │  redis    (:6379)    Cache + pub/sub (localhost)       │  │    │
│  │  └───────────────────────────────────────────────────────┘  │    │
│  │                                                              │    │
│  │  ┌─── Watchdog ─────────────────────────────────────────┐   │    │
│  │  │  watchdog            Reads health data from Redis     │  │    │
│  │  │                      (written by Status). Evaluates   │  │    │
│  │  │                      conditions, restarts layers via  │  │    │
│  │  │                      SSH (run-rollback only, NEVER    │  │    │
│  │  │                      genesis).                        │  │    │
│  │  │                      Managed layers: GL0, ML0, DL1    │  │    │
│  │  │                      3 consecutive failures → suspend │  │    │
│  │  └───────────────────────────────────────────────────────┘  │    │
│  │                                                              │    │
│  │  ┌─── Observability ────────────────────────────────────┐   │    │
│  │  │  prometheus (:9090)  Metrics (15s scrape, 30d retain) │  │    │
│  │  │  alertmanager(:9093) Alert routing → Telegram          │  │    │
│  │  │  grafana    (:3001)  Dashboards (Prometheus + Loki)    │  │    │
│  │  │  loki       (:3100)  Log aggregation (7d retention)    │  │    │
│  │  │  promtail            Docker log shipper → Loki         │  │    │
│  │  │  node-exporter(:9100)  Host metrics                    │  │    │
│  │  │  postgres-exporter(:9187)  DB metrics                  │  │    │
│  │  │  redis-exporter(:9121)     Cache metrics               │  │    │
│  │  └───────────────────────────────────────────────────────┘  │    │
│  │                                                              │    │
│  │  Network: ottochain (bridge)                                 │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  nginx (host) → SSL termination for:                                │
│    bridge.ottochain.ai  → :3030                                     │
│    explorer.ottochain.ai → :8081                                    │
│    status.ottochain.ai  → :3032                                     │
│    grafana.ottochain.ai → :3001                                     │
│    prometheus.ottochain.ai → :9090                                  │
└─────────────────────────────────────────────────────────────────────┘

                    Hetzner Private Network (10.0.0.0/16)
┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
│  NODE 1              │  │  NODE 2              │  │  NODE 3              │
│  pub: 5.78.90.207    │  │  pub: 5.78.113.25    │  │  pub: 5.78.107.77    │
│  priv: 10.0.0.4      │  │  priv: 10.0.0.2      │  │  priv: 10.0.0.3      │
│                      │  │                      │  │                      │
│  gl0 (:9000/:9001)   │  │  gl0 (:9000/:9001)   │  │  gl0 (:9000/:9001)   │
│  ml0 (:9200/:9201)   │  │  ml0 (:9200/:9201)   │  │  ml0 (:9200/:9201)   │
│  dl1 (:9400/:9401)   │  │  dl1 (:9400/:9401)   │  │  dl1 (:9400/:9401)   │
│  node-exporter(:9500)│  │  node-exporter(:9500)│  │  node-exporter(:9500)│
│  promtail            │  │  promtail            │  │  promtail            │
│                      │  │                      │  │                      │
│  /opt/ottochain/     │  │  /opt/ottochain/     │  │  /opt/ottochain/     │
│    keys/ (genesis)   │  │    keys2/            │  │    keys3/            │
│    genesis/          │  │    genesis/           │  │    genesis/           │
└──────────────────────┘  └──────────────────────┘  └──────────────────────┘

Inter-node traffic (P2P, cluster join, Prometheus scrape, Promtail→Loki)
uses private IPs. CL_EXTERNAL_IP = public IP for external peer visibility.
Genesis runs in CI — nodes cannot create genesis.
```

## Data Flow

```
Users → nginx (SSL) → gateway (:4000) → GraphQL queries
                    → bridge  (:3030) → sign + relay to DL1 nodes
                    → explorer(:8081) → read-only UI

Indexer polls ML0 snapshots → processes → writes to Postgres
Bridge relays signed transactions → fan-out to all DL1 nodes
Status polls all nodes (HTTP) → caches in Redis → serves /api/status
Watchdog reads Redis → evaluates conditions → SSH restart if needed

Traffic-gen → bridge → DL1 (synthetic load for testing)
```

## Health & Restart Flow

```
Status (polls nodes) ──→ HTTP every 60s ──→ GL0/ML0/DL1 on all 3 nodes
         │                                  (also checks public accessibility)
         ├── Caches results in Redis
         ├── Serves /api/status dashboard
         └── Sends app-level alerts (node down, snapshot stall)

Watchdog (reads Redis) ──→ Evaluates conditions from cached health data
         │                  (does NOT poll nodes directly)
         │
         ├── Healthy? → log, continue
         │
         ├── Condition triggered? → SSH to affected node
         │                         → docker compose restart <layer>
         │                         → wait 180s for Ready
         │                         → verify recovery
         │
         └── 3 consecutive failures? → SUSPEND automatic restarts
                                     → auto-resume when health recovers

Alertmanager ──→ Infrastructure alerts from Prometheus
              → Disk, memory, CPU thresholds
              → Routes to Telegram
```

## Monitoring Flow

```
node-exporter (all 4 nodes) ──→ Prometheus (scrape every 15s)
postgres-exporter             ──→ Prometheus
redis-exporter                ──→ Prometheus
metagraph JVMs (JMX metrics)  ──→ Prometheus (scrape every 30s)

Prometheus → alert rules → Alertmanager → Telegram
Prometheus → Grafana dashboards

Promtail (all 4 nodes) → reads Docker logs → ships to Loki (:3100)
Loki → Grafana log explorer
```

## Key Ports

| Port | Service | Access |
|------|---------|--------|
| 3030 | Bridge | Public (via nginx SSL) |
| 3032 | Status API | Public (via nginx SSL) |
| 4000 | Gateway/GraphQL | Public (via nginx SSL) |
| 8081 | Explorer | Public (via nginx SSL) |
| 3001 | Grafana | Public (via nginx SSL) |
| 9090 | Prometheus | Public (via nginx SSL) |
| 5432 | Postgres | localhost only |
| 6379 | Redis | localhost only |
| 3100 | Loki | Private network (metagraph nodes push via 10.x) |
| 9093 | Alertmanager | Internal |
| 9000 | GL0 (public API) | All nodes |
| 9001 | GL0 (P2P) | All nodes |
| 9200 | ML0 (public API) | All nodes |
| 9201 | ML0 (P2P) | All nodes |
| 9400 | DL1 (public API) | All nodes |
| 9401 | DL1 (P2P) | All nodes |
| 9402 | DL1 (CLI/join) | All nodes |

## Container Images

| Container | Image | Source |
|-----------|-------|--------|
| gateway, bridge, indexer, status, traffic-gen | `ghcr.io/ottobot-ai/ottochain-services` | ottochain-services repo |
| explorer | `ghcr.io/ottobot-ai/ottochain-explorer` | ottochain-explorer repo |
| watchdog | `ghcr.io/ottobot-ai/ottochain-watchdog` | ottochain-watchdog repo |
| gl0, ml0, dl1 | `ghcr.io/ottobot-ai/ottochain` | ottochain repo (tessellation) |
| postgres | `postgres:16-alpine` | Docker Hub |
| redis | `redis:7-alpine` | Docker Hub |
| prometheus | `prom/prometheus:v2.50.0` | Docker Hub |
| grafana | `grafana/grafana:10.3.1` | Docker Hub |
| loki | `grafana/loki:2.9.4` | Docker Hub |
| promtail | `grafana/promtail:2.9.4` | Docker Hub |
| alertmanager | `prom/alertmanager:v0.27.0` | Docker Hub |

## Environments

| Environment | Hypergraph | Purpose | State |
|-------------|------------|---------|-------|
| scratch | Dedicated (private) | Development testing | Active |
| beta | Constellation Testnet | Public beta testing | Planned |
| staging | Constellation IntegrationNet | Pre-production | Planned |
| prod | Constellation Mainnet | Production | Planned |

Each environment uses GitHub Environments for secrets/approvals.
Deployed state tracked in `versions.yaml` under `deployed.<env>`.
