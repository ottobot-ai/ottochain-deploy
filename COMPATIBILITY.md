# OttoChain Compatibility Matrix

> Auto-generated from `versions.yml` — do not edit manually.
> Run `scripts/generate-compatibility.sh` to update.

## Current Release

| Component | Version | Repository |
|-----------|---------|------------|
| OttoChain Metagraph | `0.5.0` | [scasplte2/ottochain](https://github.com/scasplte2/ottochain) |
| OttoChain SDK | `0.2.0` | [ottobot-ai/ottochain-sdk](https://github.com/ottobot-ai/ottochain-sdk) • [npm](https://www.npmjs.com/package/@ottochain/sdk) |
| OttoChain Services | `0.2.0` | [ottobot-ai/ottochain-services](https://github.com/ottobot-ai/ottochain-services) |
| OttoChain Explorer | `0.1.0` | [ottobot-ai/ottochain-explorer](https://github.com/ottobot-ai/ottochain-explorer) |
| Tessellation | `4.0.0-rc.2` | [Constellation-Labs/tessellation](https://github.com/Constellation-Labs/tessellation) |

## Dependency Graph

```
┌─────────────────────────────────────────────────────────┐
│                    Tessellation SDK                      │
│                     (v4.0.0-rc.2)                        │
└─────────────────────┬───────────────────────────────────┘
                      │
          ┌───────────┴───────────┐
          ▼                       ▼
┌─────────────────┐     ┌─────────────────┐
│    OttoChain    │     │  OttoChain SDK  │
│   Metagraph     │     │    (v0.2.0)     │
│    (v0.5.0)     │     │   @ottochain/sdk│
└────────┬────────┘     └────────┬────────┘
         │                       │
         │              ┌────────┴────────┐
         │              ▼                 ▼
         │    ┌─────────────────┐ ┌───────────────┐
         │    │    Services     │ │   Explorer    │
         │    │    (v0.2.0)     │ │   (v0.1.0)    │
         │    └────────┬────────┘ └───────────────┘
         │             │
         └─────────────┴──────────┐
                                  ▼
                        ┌─────────────────┐
                        │  Metagraph API  │
                        │  (ML0/DL1/CL1)  │
                        └─────────────────┘
```

## Version History

| Date | Services | SDK | Metagraph | Tessellation | Notes |
|------|----------|-----|-----------|--------------|-------|
| 2026-02-09 | 0.2.0 | 0.2.0 | 0.5.0 | 4.0.0-rc.2 | First npm release, version endpoints |
| 2026-02-04 | 0.1.0 | 0.1.0 | 0.4.0 | 4.0.0-rc.2 | Initial testnet deployment |

## Breaking Changes

### SDK 0.2.0
- Published to npmjs.com as `@ottochain/sdk` (was GitHub-only)
- Array-based commitments in market definitions

### Services 0.2.0
- Added `/version` endpoints to all services
- Docker image available at `ghcr.io/ottobot-ai/ottochain-services:v0.2.0`

## Upgrade Notes

When upgrading components:

1. **SDK → Services**: Services must use compatible SDK version
   - Check `packages/bridge/package.json` for SDK dependency
   
2. **Metagraph → Services**: Wire format must match
   - Signature algorithms and canonicalization must align
   
3. **Tessellation → Metagraph**: SDK version must match exactly
   - Check `build.sbt` for tessellation dependency version

## Verification

After deployment, verify versions match:

```bash
# Check services versions
curl -s http://services:3030/version | jq .
curl -s http://services:3031/version | jq .

# Check metagraph
curl -s http://ml0:9200/node/info | jq '.version'
```
