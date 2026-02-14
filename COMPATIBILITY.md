# OttoChain Compatibility Matrix

> Auto-generated from `versions.yml` — do not edit manually.
> Run `scripts/generate-compatibility.sh` to update.
> Generated: 2026-02-14

## Current Release

| Component | Version | Repository |
|-----------|---------|------------|
| OttoChain Metagraph | `0.5.0` | [scasplte2/ottochain](https://github.com/scasplte2/ottochain) |
| OttoChain SDK | `0.2.0` | [ottobot-ai/ottochain-sdk](https://github.com/ottobot-ai/ottochain-sdk) • [npm](https://www.npmjs.com/package/@ottochain/sdk) |
| OttoChain Services | `0.2.0` | [ottobot-ai/ottochain-services](https://github.com/ottobot-ai/ottochain-services) |
| OttoChain Explorer | `0.1.0` | [ottobot-ai/ottochain-explorer](https://github.com/ottobot-ai/ottochain-explorer) |
| Tessellation | `4.0.0-rc.2` | [Constellation-Labs/tessellation](https://github.com/Constellation-Labs/tessellation) |

## Docker Images

| Service | Image | Tag |
|---------|-------|-----|
| Services | `ghcr.io/ottobot-ai/ottochain-services` | `v0.2.0` |

## npm Packages

| Package | Version | Install |
|---------|---------|---------|
| @ottochain/sdk | `0.2.0` | `npm install @ottochain/sdk@0.2.0` |

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

## Verification

After deployment, verify versions match:

```bash
# Check services versions
curl -s http://localhost:3030/version | jq .
curl -s http://localhost:3031/version | jq .

# Check SDK version in use
npm list @ottochain/sdk

# Check metagraph
curl -s http://localhost:9200/node/info | jq '.version'
```

## Upgrade Checklist

- [ ] SDK version matches Services dependency
- [ ] Metagraph tessellation version matches cluster
- [ ] Docker images pulled with correct tags
- [ ] /version endpoints return expected values
- [ ] Integration tests pass

---

*See [versions.yml](./versions.yml) for the source of truth.*
