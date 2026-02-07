# OttoChain Deploy

Single source of truth for OttoChain deployment infrastructure.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ ottochain       │     │ ottochain-      │     │ ottochain-      │
│ (metagraph)     │     │ services        │     │ explorer        │
│                 │     │                 │     │                 │
│  CI → JAR       │     │  CI → ghcr.io   │     │  CI → ghcr.io   │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         └───────────────────────┴───────────────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │   ottochain-deploy      │
                    │                         │
                    │   versions.yml          │
                    │   compose/*.yml         │
                    │   envs/*.env            │
                    │   monitoring/*          │
                    │                         │
                    │   CD → target env       │
                    └─────────────────────────┘
```

## Quick Start

```bash
# Clone
git clone https://github.com/ottobot-ai/ottochain-deploy.git
cd ottochain-deploy

# Set up environment
cp envs/local.env .env

# Create networks
make network

# Start services
make services

# View status
make ps
```

## Compose Layers

| Layer | File | Services |
|-------|------|----------|
| **Base** | `compose/base.yml` | Redis, Postgres |
| **Services** | `compose/services.yml` | Gateway, Bridge, Indexer, Monitor |
| **Explorer** | `compose/explorer.yml` | React frontend |
| **Monitoring** | `compose/monitoring.yml` | Prometheus, Alertmanager, Grafana |
| **Exporters** | `compose/exporters.yml` | node-exporter, postgres-exporter, redis-exporter |
| **Logging** | `compose/logging.yml` | Loki, Promtail |
| **Traffic** | `compose/traffic.yml` | Traffic generator (testing) |
| **Metagraph** | `compose/metagraph.yml` | GL0, GL1, ML0, CL1, DL1 (5-layer stack) |

## Usage

### Development

```bash
# Just services (most common)
make services

# With monitoring
make full

# With log aggregation
make full-logging
```

### Manual Compose

```bash
# Layer files as needed
docker compose \
  -f compose/base.yml \
  -f compose/services.yml \
  -f compose/monitoring.yml \
  up -d
```

### Metagraph Deployment

```bash
# Genesis node (first node)
NODE_IP=1.2.3.4 make metagraph-genesis

# Validator nodes (subsequent nodes)
NODE_IP=1.2.3.5 GENESIS_IP=1.2.3.4 make metagraph-validator
```

### Commands

```bash
make help           # Show all commands
make up             # Start services (alias)
make down           # Stop everything
make logs           # Follow all logs
make logs SERVICES='gateway indexer'  # Filter logs
make ps             # List containers
make clean          # Stop + remove volumes
```

## Environments

| File | Purpose |
|------|---------|
| `envs/local.env` | Local development (Docker Desktop) |
| `envs/testnet.env` | Hetzner testnet cluster |
| `envs/prod.env.template` | Production template (copy & fill) |

```bash
# Switch environments
cp envs/testnet.env .env
# Edit .env to set passwords
make services
```

## Version Management

`versions.yml` pins all component versions:

```yaml
images:
  services: ghcr.io/ottobot-ai/ottochain-services:v1.2.3
  explorer: ghcr.io/ottobot-ai/ottochain-explorer:v1.0.0

jars:
  tessellation: "2.10.1"
  ottochain: "0.5.0"
```

To update a version:
1. Edit `versions.yml`
2. Run `make pull` to fetch new images
3. Run `make up` to deploy

## Directory Structure

```
ottochain-deploy/
├── compose/                 # Layered compose files
│   ├── base.yml
│   ├── services.yml
│   ├── explorer.yml
│   ├── metagraph.yml
│   ├── monitoring.yml
│   ├── exporters.yml
│   ├── logging.yml
│   └── traffic.yml
├── monitoring/              # Observability configs
│   ├── prometheus/
│   │   ├── prometheus.yml
│   │   ├── recording_rules.yml
│   │   └── alert_rules/
│   ├── alertmanager/
│   │   ├── alertmanager.yml
│   │   └── templates/
│   ├── grafana/provisioning/
│   ├── loki/
│   └── promtail/
├── envs/                    # Environment configs
│   ├── local.env
│   ├── testnet.env
│   └── prod.env.template
├── scripts/                 # Deployment scripts
├── docker/                  # Legacy (metagraph Dockerfiles)
├── versions.yml             # Component version pins
├── Makefile                 # Convenience commands
└── .env                     # Active environment (gitignored)
```

## Ports

| Service | Port |
|---------|------|
| Gateway | 4000 |
| Bridge | 3030 |
| Indexer | 3031 |
| Monitor | 3032 |
| Explorer | 8080 |
| Postgres | 5432 |
| Redis | 6379 |
| Prometheus | 9090 |
| Alertmanager | 9093 |
| Grafana | 3000 |
| Loki | 3100 |
| GL0 | 9000 |
| GL1 | 9100 |
| ML0 | 9200 |
| CL1 | 9300 |
| DL1 | 9400 |

## Related Repositories

- [ottochain](https://github.com/scasplte2/ottochain) — Metagraph (Scala)
- [ottochain-services](https://github.com/ottobot-ai/ottochain-services) — TypeScript services
- [ottochain-explorer](https://github.com/ottobot-ai/ottochain-explorer) — React frontend
- [ottochain-sdk](https://github.com/ottobot-ai/ottochain-sdk) — TypeScript SDK
