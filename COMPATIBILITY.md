# OttoChain Compatibility Matrix

> Auto-generated from `versions.yaml` — do not edit manually.
> Run `scripts/generate-compatibility.sh` to update.
> Generated: 2026-02-23

## Current Release

| Component | Version | Repository |
|-----------|---------|------------|
| OttoChain Metagraph | `0.7.6` | [scasplte2/ottochain](https://github.com/scasplte2/ottochain) |
| OttoChain SDK | `1.0.3` | [ottobot-ai/ottochain-sdk](https://github.com/ottobot-ai/ottochain-sdk) • [npm](https://www.npmjs.com/package/@ottochain/sdk) |
| OttoChain Services | `0.4.1` | [ottobot-ai/ottochain-services](https://github.com/ottobot-ai/ottochain-services) |
| OttoChain Explorer | `0.5.0` | [ottobot-ai/ottochain-explorer](https://github.com/ottobot-ai/ottochain-explorer) |
| OttoChain Monitoring | `0.1.0` | [ottobot-ai/ottochain-watchdog](https://github.com/ottobot-ai/ottochain-watchdog) |
| Tessellation | `4.0.0-rc.2` | [Constellation-Labs/tessellation](https://github.com/Constellation-Labs/tessellation) |

## Docker Images

| Service | Image | Tag |
|---------|-------|-----|
| Services | `ghcr.io/ottobot-ai/ottochain-services` | `v0.4.1` |
| Explorer | `ghcr.io/ottobot-ai/ottochain-explorer` | `v0.5.0` |

## npm Packages

| Package | Version | Install |
|---------|---------|---------|
| `@ottochain/sdk` | `1.0.3` | `npm install @ottochain/sdk@1.0.3` |

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
│   Metagraph     │     │    (v1.0.3)     │
│    (v0.7.6)     │     │ @ottochain/sdk  │
└────────┬────────┘     └────────┬────────┘
         │                       │
         │              ┌────────┴────────┐
         │              ▼                 ▼
         │    ┌─────────────────┐ ┌───────────────┐
         │    │    Services     │ │   Explorer    │
         │    │    (v0.4.1)     │ │   (v0.5.0)    │
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

| Date | OttoChain | SDK | Services | Explorer | Tessellation | Notes |
|------|-----------|-----|----------|----------|--------------|-------|
| 2026-02-22/23 | 0.7.6 | 1.0.3 | 0.4.1 | 0.5.0 | 4.0.0-rc.2 | SDK 1.0.1→1.0.3 (delegation + DFA patterns); OttoChain 0.7.4→0.7.6 (rejection webhook dispatch, bridge health metrics) |
| 2026-02-09 | 0.5.0 | 0.2.0 | 0.2.0 | 0.1.0 | 4.0.0-rc.2 | First npm release, version endpoints |
| 2026-02-04 | 0.4.0 | 0.1.0 | 0.1.0 | 0.1.0 | 4.0.0-rc.2 | Initial testnet deployment |

## Breaking Changes

### SDK 1.0.x
- Now at stable `1.x` semver — API considered stable
- Delegation methods: `submitDelegated()`, `revokeDelegation()` (requires PR #90 merged)
- DFA + JSON Logic patterns for state machine definitions
- Fiber State Subscription WebSocket client
- Agent Identity & Reputation (AgentProfile) SDK integration

### OttoChain 0.7.x
- Rejection webhook dispatch added (ML0 → bridge → indexer pipeline)
- Bridge health metrics endpoint
- JLVM delegation operators (delegation.* context vars in JSON Logic guards)

### SDK 0.2.0 → 0.x (historical)
- Published to npmjs.com as `@ottochain/sdk` (was GitHub-only)
- Array-based commitments in market definitions

## Compatibility Rules

Defined in [`compatibility.yaml`](./compatibility.yaml):

| Component | Requires |
|-----------|---------|
| SDK | `ottochain >= 0.5.0 < 1.0.0` |
| Services | `sdk >= 0.2.0`, `ottochain >= 0.5.0 < 1.0.0` |
| Explorer | `services >= 0.1.0` |

> Note: SDK has graduated to `1.0.x` but still requires `ottochain < 1.0.0`. The range in `compatibility.yaml` reflects what the SDK needs from the metagraph, not the SDK's own version.

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

*See [versions.yaml](./versions.yaml) for the source of truth.*
