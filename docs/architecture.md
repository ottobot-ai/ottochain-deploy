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
│  │  │  status  (:3032)     Status dashboard API              │  │    │
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
│  │  │  watchdog            Health checks + automated        │  │    │
│  │  │                      restart via SSH to metagraph     │  │    │
│  │  │                      nodes (run-rollback only,        │  │    │
│  │  │                      never genesis)                   │  │    │
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

┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
│  NODE 1 (5.78.90.207)│  │  NODE 2 (5.78.113.25)│  │  NODE 3 (5.78.107.77)│
│                      │  │                      │  │                      │
│  gl0 (:9000/:9001)   │  │  gl0 (:9000/:9001)   │  │  gl0 (:9000/:9001)   │
│  ml0 (:9200/:9201)   │  │  ml0 (:9200/:9201)   │  │  ml0 (:9200/:9201)   │
│  dl1 (:9400/:9401)   │  │  dl1 (:9400/:9401)   │  │  dl1 (:9400/:9401)   │
│  node-exporter(:9100)│  │  node-exporter(:9100)│  │  node-exporter(:9100)│
│  promtail            │  │  promtail            │  │  promtail            │
│                      │  │                      │  │                      │
│  /opt/ottochain/     │  │  /opt/ottochain/     │  │  /opt/ottochain/     │
│    keys/             │  │    keys3/            │  │    keys6/            │
│    genesis/          │  │                      │  │                      │
└──────────────────────┘  └──────────────────────┘  └──────────────────────┘
```

## Data Flow

```
Users → nginx (SSL) → gateway (:4000) → GraphQL queries
                    → bridge  (:3030) → sign + relay to DL1 nodes
                    → explorer(:8081) → read-only UI

Indexer polls ML0 snapshots → processes → writes to Postgres
Bridge relays signed transactions → fan-out to all DL1 nodes

Traffic-gen → bridge → DL1 (synthetic load for testing)
```

## Watchdog Flow

```
watchdog ─── HTTP poll ──→ GL0/ML0/DL1 on all 3 nodes (every 60s)
         │
         ├── Healthy? → log, continue
         │
         ├── Stall detected? → SSH to affected node
         │                     → docker start <layer> (run-rollback)
         │                     → wait 180s for Ready
         │                     → verify recovery
         │
         └── 3 consecutive failures? → SUSPEND automatic restarts
                                     → alert via Telegram
                                     → auto-resume when health recovers
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
| 3100 | Loki | 0.0.0.0 (metagraph nodes push logs) |
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

| Environment | Purpose | State |
|-------------|---------|-------|
| scratch | Development testing | Active |
| staging | Pre-production | Planned |
| production | Live | Planned |

Each environment uses GitHub Environments for secrets/approvals.
Deployed state tracked in `versions.yaml` under `deployed.<env>`.
