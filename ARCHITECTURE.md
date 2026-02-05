# OttoChain Distributed Deployment Architecture

## Overview

OttoChain runs as a 5-layer metagraph on Constellation's Tessellation framework.
Each layer requires 3 nodes for consensus, distributed across 3 machines.

## Layers

| Layer | JAR | Purpose | Ports |
|-------|-----|---------|-------|
| GL0 | dag-l0.jar | Global L0 - DAG consensus | 9000-9002 |
| GL1 | dag-l1.jar | Global L1 - DAG transactions | 9100-9102 |
| ML0 | metagraph-l0.jar | Metagraph L0 - OttoChain consensus | 9200-9202 |
| CL1 | currency-l1.jar | Currency L1 - OttoChain tokens | 9300-9302 |
| DL1 | data-l1.jar | Data L1 - OttoChain state machines | 9400-9402 |

## Port Convention

Each layer uses 3 ports:
- **Public HTTP** (x000): REST API, external access
- **P2P** (x001): Inter-node communication
- **CLI** (x002): Internal management

## Machine Layout

```
Machine 1 (genesis)     Machine 2 (validator)   Machine 3 (validator)
5.78.90.207             5.78.113.25             5.78.107.77
───────────────────     ───────────────────     ───────────────────
GL0-0 :9000-9002        GL0-1 :9000-9002        GL0-2 :9000-9002
GL1-0 :9100-9102        GL1-1 :9100-9102        GL1-2 :9100-9102
ML0-0 :9200-9202        ML0-1 :9200-9202        ML0-2 :9200-9202
CL1-0 :9300-9302        CL1-1 :9300-9302        CL1-2 :9300-9302
DL1-0 :9400-9402        DL1-1 :9400-9402        DL1-2 :9400-9402
```

## Startup Order

Layers must start in order, with genesis/initial-validator on Machine 1 first:

1. **GL0**: Machine 1 runs genesis, Machines 2-3 join as validators
2. **GL1**: Machine 1 runs initial-validator, Machines 2-3 join
3. **ML0**: Machine 1 runs genesis with snapshot, Machines 2-3 join
4. **CL1**: Machine 1 runs initial-validator, Machines 2-3 join
5. **DL1**: Machine 1 runs initial-validator, Machines 2-3 join

## Dependencies

```
DL1 ──→ ML0 ──→ GL0
CL1 ──→ ML0 ──→ GL0
GL1 ──→ GL0
```

- GL0 is the root (no dependencies)
- GL1 depends on GL0
- ML0 depends on GL0
- CL1 depends on ML0 (and transitively GL0)
- DL1 depends on ML0 (and transitively GL0), plus needs CL1 for currency snapshots

## Key Management

Each machine has its own keypair stored in `/opt/ottochain/keys/key.p12`.
The same key is used for all layers on that machine.

## Firewall Requirements

All machines must allow inbound TCP on:
- 9000-9002 (GL0)
- 9100-9102 (GL1)
- 9200-9202 (ML0)
- 9300-9302 (CL1)
- 9400-9402 (DL1)

From: All other metagraph machines + services server (5.78.121.248)

## Environment Variables

Each layer requires these environment variables:

```bash
# Common
CL_KEYSTORE=/keys/key.p12
CL_KEYALIAS=alias
CL_PASSWORD=<secret>
CL_APP_ENV=dev
CL_COLLATERAL=0

# Per-layer ports
CL_PUBLIC_HTTP_PORT=<public>
CL_P2P_HTTP_PORT=<p2p>
CL_CLI_HTTP_PORT=<cli>

# External IP (machine's public IP)
CL_EXTERNAL_IP=<machine-ip>

# Peer references (for validators joining)
CL_GLOBAL_L0_PEER_HTTP_HOST=<gl0-genesis-ip>
CL_GLOBAL_L0_PEER_HTTP_PORT=9000
CL_GLOBAL_L0_PEER_ID=<gl0-peer-id>

# For metagraph layers
CL_L0_PEER_HTTP_HOST=<ml0-genesis-ip>
CL_L0_PEER_HTTP_PORT=9200
CL_L0_PEER_ID=<ml0-peer-id>
CL_L0_TOKEN_IDENTIFIER=<metagraph-token-id>
```
