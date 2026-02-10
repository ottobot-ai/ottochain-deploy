# OttoChain Ecosystem Versioning Migration

**Goal:** Automated, conventional-commit-driven releases with compatibility verification across all repos.

---

## Phase 1: Core Infrastructure (ottochain-deploy)

- [x] **1.1** Create `versions.yaml` manifest schema
- [x] **1.2** Create `compatibility.yaml` matrix (which versions work together)
- [x] **1.3** Add workflow: `version-bump.yml` - receives dispatch, creates PR to bump component
- [x] **1.4** Add workflow: `validate-versions.yml` - runs on versions.yaml changes
- [x] **1.5** Add workflow: `deploy-on-merge.yml` - deploys to scratch when versions.yaml PR merges

## Phase 2: Core Metagraph (ottochain)

- [ ] **2.1** Add `release-please.yml` workflow
- [ ] **2.2** Add `release-please-config.json` for Scala project
- [ ] **2.3** Verify dispatch to ottochain-deploy works
- [ ] **2.4** Test full cycle: commit → Release PR → merge → tag → JAR + Docker → deploy notification

## Phase 3: SDK (ottochain-sdk)

- [ ] **3.1** Add `release-please.yml` workflow  
- [ ] **3.2** Add `release-please-config.json` for Node/TS project
- [ ] **3.3** Update `release.yml` to trigger on release-please tags
- [ ] **3.4** Add compatibility declaration (works with core X.Y.Z)
- [ ] **3.5** Verify npm + GitHub Packages publishing

## Phase 4: Services (ottochain-services)

- [ ] **4.1** Add `release-please.yml` workflow
- [ ] **4.2** Configure for Node monorepo (bridge, indexer, traffic-gen)
- [ ] **4.3** Add compatibility declaration (requires SDK X.Y.Z, core X.Y.Z)
- [ ] **4.4** Verify Docker image publishing

## Phase 5: Explorer (ottochain-explorer)

- [ ] **5.1** Add `release-please.yml` workflow
- [ ] **5.2** Add compatibility declaration (requires services API X.Y.Z)
- [ ] **5.3** Verify Docker image publishing

## Phase 6: Monitoring (ottochain-monitoring)

- [ ] **6.1** Add `release-please.yml` workflow
- [ ] **6.2** Minimal compatibility needs (mostly standalone)

## Phase 7: Validation & Automation

- [ ] **7.1** Add CI job to ottochain-deploy that spins up full stack and runs smoke tests
- [ ] **7.2** Add compatibility check: block deploy if SDK incompatible with core
- [ ] **7.3** Document the release process in README
- [ ] **7.4** (Optional) Add Slack/Telegram notifications for releases

---

## File Structure (ottochain-deploy)

```
ottochain-deploy/
├── versions.yaml           # Current pinned versions
├── compatibility.yaml      # Version compatibility matrix
├── .github/workflows/
│   ├── version-bump.yml    # Receives dispatch, creates bump PR
│   ├── validate.yml        # Checks compatibility on PR
│   └── deploy.yml          # Deploys on versions.yaml merge
└── scripts/
    ├── check-compatibility.ts  # Validates version combinations
    └── generate-compose.ts     # Generates docker-compose from versions
```

---

## Compatibility Matrix Format

```yaml
# compatibility.yaml
components:
  ottochain:
    type: core
    
  sdk:
    type: client
    requires:
      ottochain: ">=0.5.0"  # semver range
      
  services:
    type: backend
    requires:
      ottochain: ">=0.5.0"
      sdk: ">=0.3.0"
      
  explorer:
    type: frontend
    requires:
      services: ">=1.0.0"
```

---

## Progress Log

| Date | Task | Status | Notes |
|------|------|--------|-------|
| 2026-02-10 | Planning | ✅ | Created this doc |

