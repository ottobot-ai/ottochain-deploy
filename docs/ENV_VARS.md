# Environment Variables Reference

This document lists all environment variables used by the OttoChain services stack.

## Required Secrets (GitHub)

| Secret | Description | Example |
|--------|-------------|---------|
| `HETZNER_SSH_KEY` | SSH private key for Hetzner servers | `-----BEGIN OPENSSH...` |
| `HETZNER_NODE1_IP` | IP of node1 (metagraph layers) | `x.x.x.x` |
| `HETZNER_SERVICES_IP` | IP of services server | `x.x.x.x` |
| `POSTGRES_PASSWORD` | PostgreSQL password | `secure-password` |
| `METAGRAPH_ID` | *(auto-fetched from node1)* | Generated at metagraph build |
| `TELEGRAM_ALERT_BOT_TOKEN` | Telegram bot token for alerts | `123456:ABC...` |
| `TELEGRAM_ALERT_CHAT_ID` | Telegram chat ID for alerts | `-100123456789` |

## Service Environment Variables

### All Services (Shared)

| Variable | Required | Description |
|----------|----------|-------------|
| `NODE_ENV` | Yes | `development`, `production`, or `test` |
| `DATABASE_URL` | Yes | PostgreSQL connection string |
| `REDIS_URL` | Yes | Redis connection string |
| `METAGRAPH_ML0_URL` | Yes | ML0 (metagraph L0) endpoint |
| `METAGRAPH_DL1_URL` | Yes | DL1 (data L1) endpoint |
| `GL0_URL` | Yes | GL0 (global L0) endpoint for confirmations |
| `METAGRAPH_ID` | Recommended | DAG address for GL0 confirmation matching |

### Gateway

| Variable | Required | Description |
|----------|----------|-------------|
| `GATEWAY_PORT` | No | Port (default: 4000) |

### Bridge

| Variable | Required | Description |
|----------|----------|-------------|
| `BRIDGE_PORT` | No | Port (default: 3030) |

### Indexer

| Variable | Required | Description |
|----------|----------|-------------|
| `INDEXER_PORT` | No | Port (default: 3031) |
| `INDEXER_CALLBACK_URL` | No | Webhook URL for ML0 to notify |
| `GL0_POLL_INTERVAL` | No | GL0 polling interval in ms (default: 5000) |
| `ML0_POLL_INTERVAL` | No | ML0 polling interval in ms (default: 5000) |

### Monitor

| Variable | Required | Description |
|----------|----------|-------------|
| `MONITOR_PORT` | No | Port (default: 3032) |
| `MONITOR_AUTH` | No | Enable basic auth |
| `MONITOR_USER` | No | Basic auth username |
| `MONITOR_PASS` | No | Basic auth password |

### Traffic Generator

| Variable | Required | Description |
|----------|----------|-------------|
| `BRIDGE_URL` | Yes | Internal bridge URL |
| `INDEXER_URL` | Yes | Internal indexer URL |
| `ML0_URL` | Yes | ML0 endpoint |
| `TRAFFIC_INTERVAL` | No | Interval between batches (ms) |
| `TRAFFIC_BATCH_SIZE` | No | Transactions per batch |

### Alerting

| Variable | Required | Description |
|----------|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | No | Telegram bot for alerts |
| `TELEGRAM_CHAT_ID` | No | Chat to send alerts |
| `ALERT_WEBHOOK_URL` | No | Generic webhook for alerts |
| `ALERT_WEBHOOK_SECRET` | No | HMAC secret for webhook |

## Metagraph Layer Ports

| Layer | Port | Description |
|-------|------|-------------|
| GL0 | 9000 | Global L0 |
| GL1 | 9100 | Global L1 |
| ML0 | 9200 | Metagraph L0 (currency + consensus) |
| CL1 | 9300 | Currency L1 |
| DL1 | 9400 | Data L1 (state machines) |

## Data Flow

```
Client → Bridge → DL1 (validate) → ML0 (consensus) → GL0 (global snapshot)
                                        ↓
                              Webhook → Indexer → PostgreSQL
                                        ↓
                                     Gateway ← GraphQL queries
```

The indexer needs `GL0_URL` to confirm that ML0 snapshots have been included
in global snapshots. Without it, snapshots remain in PENDING state.
