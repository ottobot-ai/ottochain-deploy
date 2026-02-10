# OttoChain Build & Deploy System Audit

*Generated: 2026-02-09*

## Executive Summary

The ecosystem has a solid Docker-based deploy system with version management via `versions.yml`. Metagraph releases are now fully supported via Docker images (PR #39 + PR #21). All P0 items complete. Remaining work: SDK auto-publish, rollback workflow, deploy plan/diff.

---

## Release Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                     OTTOCHAIN RELEASE PIPELINE                       │
└─────────────────────────────────────────────────────────────────────┘

1. TAG A VERSION IN COMPONENT REPO
   git tag v0.5.0 && git push --tags
              │
              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  scasplte2/ottochain                                                │
│  ┌──────────────────┐    ┌──────────────────┐                       │
│  │ release.yml      │    │ docker.yml       │  (both trigger on v*) │
│  │ (JAR artifacts)  │    │ (Docker image)   │                       │
│  └────────┬─────────┘    └────────┬─────────┘                       │
│           │                       │                                  │
│           ▼                       ▼                                  │
│  • Build 3 JARs (sbt)    • Build Docker image                       │
│  • Upload to GH Release  • Push to ghcr.io/ottobot-ai/ottochain     │
│  • Notify deploy repo    • Notify deploy repo                       │
└───────────┬──────────────────────┬──────────────────────────────────┘
            │                      │
            └──────────┬───────────┘
                       ▼
┌─────────────────────────────────────────────────────────────────────┐
│  ottobot-ai/ottochain-deploy                                        │
│  ┌──────────────────────────────────────────────────────┐           │
│  │ version-bump.yml (receives repository_dispatch)      │           │
│  │ • Updates versions.yml                               │           │
│  │ • Creates PR: "Release: ottochain v0.5.0"            │           │
│  └───────────────────────┬──────────────────────────────┘           │
│                          ▼                                          │
│  Human merges PR → push to release/scratch                          │
│                          │                                          │
│  ┌───────────────────────▼──────────────────────────────┐           │
│  │ release-scratch.yml                                   │           │
│  │ • Deploys to Hetzner cluster                         │           │
│  │ • Runs smoke tests                                   │           │
│  └──────────────────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│  Similar flow for other components:                                  │
│  • ottochain-services  → release.yml → Docker + dispatch            │
│  • ottochain-explorer  → release.yml → Docker + dispatch            │
│  • ottochain-sdk       → release.yml → npm publish + dispatch       │
│  • ottochain-monitoring → release.yml → dispatch                    │
└─────────────────────────────────────────────────────────────────────┘
```

### What Gets Built

| Component | Artifacts | Destination |
|-----------|-----------|-------------|
| **ottochain** | 3 JARs (metagraph-l0, currency-l1, data-l1) | GitHub Releases |
| **ottochain** | Docker image (all 5 layers) | `ghcr.io/ottobot-ai/ottochain-metagraph` |
| **services** | Docker image (bridge + indexer + monitor) | `ghcr.io/ottobot-ai/ottochain-services` |
| **explorer** | Docker image (web UI) | `ghcr.io/ottobot-ai/ottochain-explorer` |
| **sdk** | npm package | `@ottochain/sdk` on npm |

### JARs vs Docker

**Docker image** (recommended for deployment):
- Single image contains all 5 layers
- Layer selection via `LAYER=ml0` env var
- No build on deploy — just pull and run
- Used by deploy workflows

**JARs** (available for):
- Manual/custom deployments without Docker
- Tessellation euclid-based setups
- Archive/audit trail on GitHub Releases
- Debugging specific layer issues

---

## Current Architecture

### Repositories

| Repo | Purpose | Artifacts | Release Flow |
|------|---------|-----------|--------------|
| `scasplte2/ottochain` | Metagraph Scala code | Docker image (all 5 layers) | ✅ `ghcr.io/ottobot-ai/ottochain-metagraph` (PR #39) |
| `ottobot-ai/ottochain-sdk` | TypeScript SDK | npm package | ✅ `v0.2.0` |
| `ottobot-ai/ottochain-services` | Bridge/Indexer | Docker image | ✅ `v0.2.0` |
| `ottobot-ai/ottochain-explorer` | Web UI | Docker image | ✅ `v0.1.0` |
| `ottobot-ai/ottochain-deploy` | Deploy configs | Workflows | Pure Docker (PR #21) |
| `ottobot-ai/ottochain-monitoring` | Monitoring stack | Prometheus/Grafana configs | Deployed via `deploy-monitoring.yml` |

### Docker-First Architecture (NEW)

**PR #39 (ottochain)** + **PR #21 (deploy)** introduce a Docker-first approach:

1. **Single metagraph image** (`ghcr.io/ottobot-ai/ottochain-metagraph`) contains all 5 layers:
   - GL0, GL1 (Tessellation)
   - ML0, CL1, DL1 (OttoChain)
   
2. **Layer selection via env var**: `LAYER=ml0` determines which JAR runs

3. **No build on deploy**: Workflows pull pre-built images instead of compiling JARs

4. **Version lock**: Tessellation + OttoChain versions baked together = guaranteed compatibility

### Version Management

**Source of truth**: `ottochain-deploy/versions.yml`

```yaml
components:
  ottochain:     { version: "0.5.0", repo: "scasplte2/ottochain" }
  tessellation:  { version: "4.0.0-rc.2" }
  sdk:           { version: "0.2.0", package: "@ottochain/sdk" }
  services:      { version: "0.2.0", image: "ghcr.io/..." }
  explorer:      { version: "0.1.0", image: "ghcr.io/..." }
```

### Deploy Workflows

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `deploy-full.yml` | Push to `release/*` branches, manual | Full stack deployment |
| `deploy-metagraph.yml` | Called by deploy-full | Pull Docker image, deploy 5-layer cluster |
| `deploy-services.yml` | Called by deploy-full | Docker compose on services node |
| `deploy-monitoring.yml` | Called by deploy-full | Prometheus/Grafana/Alertmanager stack |

### Monitoring Stack

**Repository**: `ottobot-ai/ottochain-monitoring`

**Components** (from `versions.yml`):
| Component | Version | Purpose |
|-----------|---------|---------|
| Prometheus | v2.50.0 | Metrics collection |
| Grafana | 10.3.1 | Dashboards |
| Alertmanager | v0.27.0 | Alert routing |
| Loki | 2.9.4 | Log aggregation |
| Promtail | 2.9.4 | Log shipping |
| node_exporter | v1.7.0 | Host metrics |
| postgres_exporter | v0.15.0 | Postgres metrics |
| redis_exporter | v1.56.0 | Redis metrics |

**Deployment**:
1. `deploy-monitoring.yml` clones `ottochain-monitoring` repo
2. Generates `prometheus/targets.yml` with cluster node IPs
3. Deploys Docker compose stack to services node
4. Optionally deploys node-exporter to metagraph nodes (`include_exporters` flag)

**Targets auto-discovered**:
- Node exporters on all 3 metagraph nodes (port 9100)
- Tessellation layers on each node (ports 9000, 9100, 9200, 9300, 9400)
- Services node exporters (Postgres, Redis)

**Access**:
- Grafana: `http://services-ip:3000`
- Prometheus: `http://services-ip:9090`
- Alertmanager: `http://services-ip:9093`

---

## How to Release a New Version

### 1. Services or Explorer (TypeScript)

```bash
# In component repo
git tag v0.3.0
git push origin v0.3.0

# This triggers release.yml which:
# - Builds Docker image
# - Pushes to ghcr.io
# - Creates GitHub Release
```

Then update versions.yml:
```bash
cd ottochain-deploy
# Edit versions.yml: services.version = "0.3.0"
git commit -am "chore: bump services to v0.3.0"
git push origin main
```

### 2. OttoChain SDK (npm)

```bash
cd ottochain-sdk
npm version patch  # or minor/major
git push origin main --tags

# Publish to npm
npm publish --access public
```

Then update versions.yml in deploy repo.

### 3. OttoChain Metagraph (Scala)

**Currently**: No release workflow. JARs built from branch/commit at deploy time.

```bash
# Update versions.yml
components:
  ottochain:
    version: "0.6.0"  # Semantic version for tracking
    ref: "v0.6.0"     # Git ref to build from (tag/branch/sha)
```

---

## Deploying a Compatible Set

### Option A: Full Stack Deploy (Recommended)

```bash
# From GitHub Actions UI:
# 1. Go to ottochain-deploy → Actions → Deploy Full Stack
# 2. Select environment (scratch/beta/staging/prod)
# 3. Optionally override versions
# 4. Run workflow
```

Or via push:
```bash
cd ottochain-deploy
git checkout release/scratch
git merge main
git push origin release/scratch
# Triggers deploy-full.yml automatically
```

### Option B: Individual Component Deploy

```bash
# Metagraph only
gh workflow run deploy-metagraph.yml \
  -f environment=scratch \
  -f metagraph_version=main \
  -f wipe_state=false

# Services only
gh workflow run deploy-services.yml \
  -f environment=scratch \
  -f services_version=v0.2.0

# Monitoring only
gh workflow run deploy-monitoring.yml \
  -f environment=scratch
```

### Verification After Deploy

```bash
# Check services versions
curl -s http://services-ip:3030/version | jq .
curl -s http://services-ip:8080/api/version | jq .

# Check metagraph
curl -s http://node1-ip:9200/version | jq .  # ML0
curl -s http://node1-ip:9400/version | jq .  # DL1

# Check monitoring
curl -s http://services-ip:9090/-/healthy  # Prometheus
curl -s http://services-ip:3000/api/health | jq .  # Grafana

# Check deployed state in versions.yml
yq '.deployed.scratch' versions.yml
```

---

## Identified Gaps

### ✅ Recently Solved

1. **Metagraph releases** — SOLVED by PR #39 + PR #21
   - Multi-stage Dockerfile builds all 5 layers into single image
   - Pushed to `ghcr.io/ottobot-ai/ottochain-metagraph`
   - Deploy workflows pull image instead of building JARs
   - Rollback = deploy previous image tag

2. **Automated version bump PRs** — SOLVED by this PR
   - Component repos send `repository_dispatch` after release
   - `version-bump.yml` receives dispatch, creates PR updating `versions.yml`
   - Human reviews/merges → triggers deploy
   - Implemented in: ottochain (#42), services (#67), explorer (#25), monitoring (#1)

### 🔴 Critical

(None remaining)

### 🟡 Important

1. **SDK not auto-published on tag**
   - release.yml builds Docker but SDK publish is manual
   - Should `npm publish` in the workflow
   
4. **No integration test gate before deploy**
   - deploy-full.yml doesn't run integration tests
   - Could deploy broken combination
   
   **Recommendation**: Add job that runs services integration tests before deploy

5. **Deployed state tracking incomplete**
   - `versions.yml` has `deployed:` section but it's updated after deploy
   - No pre-deploy diff showing what will change
   
   **Recommendation**: Add "Plan" step showing version changes before deploy

### 🟢 Minor

6. **No rollback workflow**
   - Manual process to deploy previous versions
   - Could add `rollback.yml` that reads last good deploy

7. **Environment-specific version overrides**
   - Currently all envs use same versions.yml
   - Beta might need different versions than prod
   
   **Recommendation**: Support `versions.{env}.yml` overrides

8. **Missing health check retry loop**
   - deploy-services.yml checks health once
   - Should retry with backoff for slow starts

---

## Version Compatibility Rules

```
Tessellation SDK ←── exact match ──→ OttoChain Metagraph
        │
        └── build dep ──→ OttoChain SDK ←── package dep ──→ Services
                                                    │
                                                    └──→ Explorer
```

**Constraints**:
- Metagraph's `build.sbt` tessellation version MUST match cluster
- Services' `package.json` SDK version should match latest published
- Explorer uses Services API (backward compatible expected)

---

## Proposed Enhanced Workflow

```
┌──────────────────────────────────────────────────────────────────┐
│                    Component Repo (e.g. services)                 │
│  1. PR merged to main                                            │
│  2. Dev decides to release                                       │
│  3. git tag v0.3.0 && git push --tags                           │
│  4. release.yml: build image → push ghcr → create GH release    │
│  5. Webhook to deploy repo: "services v0.3.0 released"          │
└─────────────────────────────┬────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Deploy Repo                                    │
│  6. version-bump.yml: create PR updating versions.yml            │
│  7. Human reviews, approves, merges                              │
│  8. Push to release/scratch triggers deploy-full.yml             │
│  9. Integration tests run first                                  │
│  10. If pass: deploy metagraph → services → monitoring          │
│  11. Update deployed state in versions.yml                       │
│  12. Notify success/failure                                      │
└──────────────────────────────────────────────────────────────────┘
```

---

## Quick Reference

### Propose New Version
```bash
# Edit versions.yml, create PR
cd ottochain-deploy
vim versions.yml  # bump component version
./scripts/generate-compatibility.sh
git add -A && git commit -m "chore: bump services to v0.3.0"
gh pr create --title "Release: services v0.3.0"
```

### Deploy to Scratch
```bash
# After PR merged
git checkout release/scratch
git merge main
git push origin release/scratch
# Or: gh workflow run deploy-full.yml -f environment=scratch
```

### Check What's Deployed
```bash
yq '.deployed' versions.yml
# Or check live:
curl -s http://5.78.121.248:8080/api/version | jq .
```

### Emergency Rollback
```bash
# Revert versions.yml to previous commit
git revert HEAD
git push origin release/scratch
# Triggers redeploy with previous versions
```

---

## Action Items

| Priority | Item | Status | Effort |
|----------|------|--------|--------|
| P0 | Add metagraph release workflow | ✅ Done (PR #39) | 2h |
| P0 | Add version-bump automation | ✅ Done (this PR) | 3h |
| P1 | Add smoke test gate | ✅ Done (smoke-test.yml) | 2h |
| P1 | Add SDK auto-publish to npm | TODO | 1h |
| P2 | Add rollback workflow | TODO | 1h |
| P2 | Add deploy plan/diff step | TODO | 1h |
