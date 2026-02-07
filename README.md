# OttoChain Deploy

Deployment scripts, CI/CD workflows, and infrastructure configuration for OttoChain metagraph.

## Architecture

OttoChain runs as a 5-layer metagraph on Constellation Network's Tessellation framework:

- **GL0** - Global L0 (DAG consensus)
- **GL1** - Global L1 (DAG transactions)
- **ML0** - Metagraph L0 (OttoChain state machine consensus)
- **CL1** - Currency L1 (OTTO token transactions)
- **DL1** - Data L1 (fiber/contract data updates)

Each layer runs on 3 nodes for Byzantine fault tolerance.

## Repository Structure

```
├── .github/workflows/     # CI/CD pipelines
│   └── release-scratch.yml  # Full cluster deploy from genesis
├── docker/
│   └── metagraph/         # Docker Compose for metagraph nodes
├── services/              # Explorer, bridge, indexer, monitor
└── docs/                  # Deployment and operations guides
```

## Deployment

Deployments are triggered via GitHub Actions:

1. **Push to `release/scratch`** - Full wipe and redeploy from genesis
2. **Manual workflow dispatch** - Options for skip-build, partial deploys

See `DEPLOYMENT.md` for manual deployment instructions.

## Services

- **Gateway** - HTTP API for transaction submission
- **Bridge** - Connects to metagraph nodes
- **Indexer** - Indexes snapshots into PostgreSQL
- **Monitor** - Health checks and status dashboard
- **Explorer** - Web UI (planned)

## Related Repositories

- [ottochain](https://github.com/ottobot-ai/ottochain) - Core metagraph implementation
- [tessellation](https://github.com/Constellation-Labs/tessellation) - Constellation Network framework

## License

Private - All rights reserved.
