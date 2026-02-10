# OttoChain Ecosystem Architecture

> A predictable, automated deployment system for multi-environment consistency.

---

## 1. Repository Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                      UPSTREAM (read-only)                       │
├─────────────────────────────────────────────────────────────────┤
│  Constellation-Labs/tessellation    ← L0/L1 framework           │
│  Constellation-Labs/metakit         ← Metagraph toolkit         │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CORE (scasplte2 owned)                       │
├─────────────────────────────────────────────────────────────────┤
│  scasplte2/ottochain               ← Metagraph implementation   │
│    branches: main, develop                                      │
│    releases: v0.6.0, v0.6.1, ...                               │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   ECOSYSTEM (ottobot-ai owned)                  │
├─────────────────────────────────────────────────────────────────┤
│  ottochain-sdk        ← TypeScript client library               │
│  ottochain-services   ← Bridge, indexer, API                    │
│  ottochain-explorer   ← Web UI                                  │
│  ottochain-monitoring ← Grafana, Prometheus, alerts             │
│  ottochain-deploy     ← Deployment orchestration (this repo)    │
│    branches: main, develop                                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Branch Strategy

All repos follow the same pattern:

```
main ─────────────────────────► (stable releases)
  ▲                              │
  │ merge when ready             │ release-please watches
  │                              ▼
develop ──────────────────────► (integration branch)
  ▲     ▲     ▲
  │     │     │
feat/A fix/B feat/C             (feature branches)
```

### Rules

| Branch | Purpose | Deploys To | Release-Please |
|--------|---------|------------|----------------|
| `main` | Stable releases | staging, prod | ✅ Watches |
| `develop` | Integration testing | scratch, beta | ❌ Ignored |
| `feat/*` | Feature work | PR preview (future) | ❌ Ignored |

### Conventional Commits

All commits to `develop` and `main` must follow conventional commits:

```
feat: add new feature        → minor bump
fix: resolve issue           → patch bump  
feat!: breaking change       → major bump
BREAKING CHANGE: in body     → major bump
chore: maintenance           → no bump (hidden)
docs: documentation          → no bump (hidden)
```

---

## 3. Environment Strategy

### Environment Definitions

| Environment | Purpose | Source Mode | Auto-Deploy | Stability |
|-------------|---------|-------------|-------------|-----------|
| `scratch` | Rapid iteration | Branch | On push | Unstable |
| `beta` | Integration testing | Branch | On push to develop | Semi-stable |
| `staging` | Pre-prod validation | Version (RC) | Manual promote | Stable |
| `prod` | Production | Version | Manual promote | Locked |

### Environment Manifests

Each environment has a manifest defining exact sources:

```yaml
# environments/scratch.yaml
name: scratch
mode: branch
auto_deploy: true

sources:
  tessellation:
    type: upstream
    repo: Constellation-Labs/tessellation
    ref: main  # or custom branch
    
  metakit:
    type: upstream
    repo: Constellation-Labs/metakit
    ref: main
    build_with:
      tessellation: ${tessellation.ref}
      
  ottochain:
    type: core
    repo: scasplte2/ottochain
    ref: develop
    build_with:
      tessellation: ${tessellation.ref}
      metakit: ${metakit.ref}
      
  sdk:
    type: ecosystem
    repo: ottobot-ai/ottochain-sdk
    ref: develop
    
  services:
    type: ecosystem
    repo: ottobot-ai/ottochain-services
    ref: develop
    
  explorer:
    type: ecosystem
    repo: ottobot-ai/ottochain-explorer
    ref: develop
    
  monitoring:
    type: ecosystem
    repo: ottobot-ai/ottochain-monitoring
    ref: develop

infrastructure:
  cluster: hetzner-scratch
  nodes: [node1, node2, node3]
  services_host: services-scratch
```

```yaml
# environments/prod.yaml
name: prod
mode: version
auto_deploy: false

sources:
  tessellation:
    type: upstream
    version: v4.0.0
    
  metakit:
    type: upstream
    version: v0.2.0
    
  ottochain:
    type: core
    version: v0.6.1
    
  sdk:
    type: ecosystem
    version: v0.3.0
    
  services:
    type: ecosystem
    version: v1.0.0
    
  explorer:
    type: ecosystem
    version: v1.0.0
    
  monitoring:
    type: ecosystem
    version: v0.1.0

infrastructure:
  cluster: hetzner-prod
  nodes: [prod-node1, prod-node2, prod-node3]
  services_host: services-prod
```

---

## 4. Dependency Cascade

When upstream changes, the cascade flows down:

```
tessellation (Constellation-Labs)
     │
     ▼ (compile dependency)
metakit (Constellation-Labs)
     │
     ▼ (compile dependency)
ottochain (scasplte2)
     │
     ├────────────────┐
     ▼                ▼
   JARs            SDK (types must match)
     │                │
     ▼                ▼
  Docker          services (uses SDK)
  Image               │
     │                ▼
     └────────────► explorer (uses services API)
```

### Build Order

For branch-based deploys, builds must happen in order:

1. **tessellation** → `publishLocal` (if custom)
2. **metakit** → `publishLocal` (if custom, with tessellation)
3. **ottochain** → `sbt assembly` → Docker image
4. **sdk** → `npm run build` (types from ottochain)
5. **services** → Docker image (with sdk)
6. **explorer** → Docker image (with services types)

### Compatibility Matrix

```yaml
# compatibility.yaml
compatibility:
  # SDK must match ottochain data types
  sdk:
    ottochain: ">=0.5.0 <1.0.0"
    
  # Services need compatible SDK and understand ottochain snapshots
  services:
    sdk: ">=0.2.0"
    ottochain: ">=0.5.0 <1.0.0"
    
  # Explorer talks to services API
  explorer:
    services: ">=0.1.0"
```

---

## 5. Deployment Workflows

### Branch Deploy (scratch/beta)

```yaml
# .github/workflows/deploy-branch.yml
name: Deploy Branch

on:
  push:
    branches: [develop]
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [scratch, beta]
      ottochain_ref:
        description: 'OttoChain branch/SHA'
        default: 'develop'

jobs:
  build-chain:
    # Build in dependency order
    steps:
      - name: Build ottochain
        # Checkout ref, build with specified deps
        
      - name: Build SDK
        # Must use same types as ottochain
        
      - name: Build services
        # Uses SDK from previous step
        
      - name: Build explorer
        # Uses services types
        
  deploy:
    needs: build-chain
    # Deploy all components to environment
```

### Version Deploy (staging/prod)

```yaml
# .github/workflows/deploy-version.yml
name: Deploy Version

on:
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [staging, prod]

jobs:
  validate:
    steps:
      - name: Load environment manifest
      - name: Verify all versions exist
      - name: Check compatibility matrix
      
  deploy:
    needs: validate
    # Pull pre-built artifacts by version
    # Deploy to environment
```

### Promotion Workflow

```yaml
# .github/workflows/promote.yml
name: Promote Environment

on:
  workflow_dispatch:
    inputs:
      from:
        type: choice
        options: [scratch, beta, staging]
      to:
        type: choice
        options: [beta, staging, prod]

jobs:
  promote:
    steps:
      - name: Snapshot current state of $from
      - name: Generate version manifest
      - name: Create promotion PR for $to
      - name: Require approval for prod
```

---

## 6. Lockfile System

When a deployment works, capture exact state:

```yaml
# lockfiles/scratch-2026-02-10-1423.yaml
timestamp: 2026-02-10T14:23:00Z
environment: scratch
status: healthy

sources:
  tessellation:
    repo: Constellation-Labs/tessellation
    ref: main
    sha: abc123def456
    
  metakit:
    repo: Constellation-Labs/metakit  
    ref: main
    sha: 789ghi012jkl
    
  ottochain:
    repo: scasplte2/ottochain
    ref: develop
    sha: mno345pqr678
    
  sdk:
    repo: ottobot-ai/ottochain-sdk
    ref: develop
    sha: stu901vwx234
    version: 0.2.1-dev.5
    
  services:
    repo: ottobot-ai/ottochain-services
    ref: develop
    sha: yza567bcd890
    
  explorer:
    repo: ottobot-ai/ottochain-explorer
    ref: develop
    sha: efg123hij456

artifacts:
  ottochain_image: ghcr.io/scasplte2/ottochain-metagraph:develop-mno345p
  services_image: ghcr.io/ottobot-ai/ottochain-services:develop-yza567b
  explorer_image: ghcr.io/ottobot-ai/ottochain-explorer:develop-efg123h

tests:
  smoke: passed
  e2e: passed
```

### Using Lockfiles

```bash
# Replay a known-good state
./scripts/deploy-from-lockfile.sh lockfiles/scratch-2026-02-10-1423.yaml

# Promote lockfile to staging manifest
./scripts/promote-lockfile.sh scratch-2026-02-10-1423.yaml staging
```

---

## 7. Release Flow

### Feature Development

```
1. Create feat/my-feature from develop
2. Work, commit with conventional commits
3. PR to develop
4. CI runs, PR reviewed, merged
5. develop auto-deploys to scratch/beta
6. Integration testing
```

### Release Preparation

```
1. develop is stable, tested
2. PR develop → main
3. CI validates, PR reviewed
4. Merge to main
5. release-please creates Release PR
6. Review changelog, merge Release PR
7. Tag created (v0.7.0)
8. Artifacts built (JARs, Docker images, npm)
9. Deploy repo notified
10. Staging deployment PR created
```

### Production Release

```
1. Staging has been validated
2. Trigger promote workflow (staging → prod)
3. Generates prod manifest from staging versions
4. Creates PR requiring approval
5. Approved, merged
6. Production deployment runs
```

---

## 8. Agent Interaction Model

Agents can predictably interact with this system:

### Query State

```bash
# What's deployed where?
cat environments/scratch.yaml
cat environments/prod.yaml

# What versions are compatible?
cat compatibility.yaml

# What combinations are known-good?
ls lockfiles/
```

### Make Changes

```bash
# Update scratch to test a branch
yq -i '.sources.ottochain.ref = "feat/my-feature"' environments/scratch.yaml
git commit -m "chore(scratch): test feat/my-feature"
git push  # triggers deploy

# Promote to next environment
gh workflow run promote.yml -f from=scratch -f to=beta
```

### Guarantees

1. **Deterministic**: Same manifest = same deployment
2. **Traceable**: Lockfiles capture exact state
3. **Validated**: Compatibility checked before deploy
4. **Ordered**: Dependencies built in correct order
5. **Reversible**: Can replay any lockfile

---

## 9. Implementation Phases

### Phase 1: Foundation ✅
- [x] release-please in all repos
- [x] develop branches in all repos
- [x] versions.yaml manifest
- [x] compatibility.yaml matrix

### Phase 2: Environment Manifests
- [ ] Create environments/ directory structure
- [ ] Add scratch.yaml, beta.yaml, staging.yaml, prod.yaml
- [ ] Update deploy workflows to read manifests

### Phase 3: Branch Builds
- [ ] Build workflow that handles branch sources
- [ ] Proper dependency ordering
- [ ] Artifact tagging with SHA

### Phase 4: Lockfiles
- [ ] Lockfile generation on successful deploy
- [ ] Deploy-from-lockfile script
- [ ] Lockfile promotion script

### Phase 5: Promotion Workflow
- [ ] promote.yml workflow
- [ ] Approval gates for prod
- [ ] Slack/Telegram notifications

### Phase 6: Validation
- [ ] Compatibility check CI job
- [ ] Smoke test runner
- [ ] E2E test integration

---

## 10. Quick Reference

### For Developers

```bash
# Start feature
git checkout develop
git pull
git checkout -b feat/my-feature

# Work...
git commit -m "feat: add thing"

# Submit
gh pr create --base develop

# After merge, it auto-deploys to scratch
```

### For Releases

```bash
# Merge develop to main when ready
gh pr create --base main --head develop --title "Release batch"

# After merge, release-please creates Release PR
# Review and merge Release PR
# Tag created, artifacts built, staging notified
```

### For Operations

```bash
# Check environment status
cat environments/scratch.yaml

# Deploy specific versions to staging
yq -i '.sources.ottochain.version = "0.7.0"' environments/staging.yaml
git commit -m "chore(staging): bump ottochain to 0.7.0"
git push

# Promote to prod (requires approval)
gh workflow run promote.yml -f from=staging -f to=prod
```
