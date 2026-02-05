# OttoChain Deployment (Private)

Deployment scripts and documentation for OttoChain metagraph infrastructure.

**DO NOT MAKE PUBLIC** - Contains server IPs and infrastructure details.

## Infrastructure

| IP | Hostname | Role |
|----|----------|------|
| 5.78.90.207 | ottochain-beta-1 | Metagraph node 1 (genesis) |
| 5.78.113.25 | ottochain-beta-2 | Metagraph node 2 |
| 5.78.107.77 | ottochain-beta-3 | Metagraph node 3 |
| 5.78.121.248 | agent-bridge | Services (indexer, explorer, bridge) |

## Quick Start

```bash
# SSH to any node
ssh -i ~/.ssh/hetzner_ottobot root@5.78.90.207

# Run status check
/opt/ottochain/scripts/status.sh

# Restart full cluster
/opt/ottochain/scripts/start-all.sh
```

## Contents

- `DEPLOYMENT.md` - Full build and deployment guide
- `scripts/` - Restart and management scripts
