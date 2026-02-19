# OttoChain Release Runbook

> **Audience:** Developers and agents releasing OttoChain ecosystem components  
> **Last updated:** 2026-02-18  
> **Automation status:** Phases 1–2 automated, Phases 3–5 partially automated (see [VERSIONING-MIGRATION.md](VERSIONING-MIGRATION.md))

---

## Overview

The OttoChain ecosystem consists of four independently versioned components with a strict dependency order:

```
ottochain (metagraph)
    ↓ depends on tessellation SDK
ottochain-sdk
    ↓ provides TypeScript client types
ottochain-services (bridge, indexer, traffic-gen)
    ↓ provides REST API
ottochain-explorer
```

**Release order must follow this dependency chain.** Releasing `services` before `sdk` causes type mismatches. Releasing `explorer` before `services` causes broken API calls.

Versions are tracked in [`versions.yaml`](versions.yaml). The compatibility matrix lives in [`COMPATIBILITY.md`](COMPATIBILITY.md) (auto-generated from `compatibility.yaml`).

---

## Quick Reference

| Component | Repo | Release method | Artifact |
|-----------|------|---------------|---------|
| `ottochain` | `scasplte2/ottochain` | release-please → tag | GitHub Release + JAR (CI) |
| `ottochain-sdk` | `ottobot-ai/ottochain-sdk` | release-please → tag | npm package + GitHub Packages |
| `ottochain-services` | `ottobot-ai/ottochain-services` | release-please → tag | Docker image → ghcr.io |
| `ottochain-explorer` | `ottobot-ai/ottochain-explorer` | release-please → tag | Docker image → ghcr.io |

---

## Part 1: Pre-Release Checklist

Before triggering any release, verify:

### 1.1 Tests

- [ ] CI is green on `develop` for all affected repos
- [ ] No open P0 bugs in that component
- [ ] Integration tests pass against scratch environment

```bash
# Check CI status via GitHub CLI
gh run list --repo scasplte2/ottochain --branch develop --limit 5
gh run list --repo ottobot-ai/ottochain-services --branch develop --limit 5
```

### 1.2 Changelog

- [ ] All changes use [Conventional Commits](https://www.conventionalcommits.org/) format
  - `feat:` → minor bump
  - `fix:` → patch bump
  - `feat!:` or `BREAKING CHANGE:` footer → major bump
- [ ] release-please has generated a Release PR (check open PRs in the repo)

### 1.3 Compatibility

- [ ] `COMPATIBILITY.md` reflects current known-good versions (run `scripts/generate-compatibility.sh` if needed)
- [ ] If this is a **breaking change**, the dependent components are ready to release too (schedule them in the same release window)

### 1.4 Coordination

- [ ] Notify James if any breaking changes are involved
- [ ] For cross-repo changes, coordinate timing so the dependency chain releases in order within ~1 hour

---

## Part 2: Release Procedure (Normal — Automated)

### Step 1: Merge the release-please PR

Each repo has an auto-maintained "Release PR" created by the `release-please.yml` workflow. When ready to release:

1. Navigate to the repo's open PRs
2. Find the release-please PR (title: `chore(main): release vX.Y.Z`)
3. Verify the changelog entries are correct
4. **Merge the PR** — this triggers:
   - Tag creation (`vX.Y.Z`)
   - GitHub Release creation with changelog
   - Artifact build (JAR or Docker image)
   - (For `ottochain`) dispatch to `ottochain-deploy` to bump `versions.yaml`

```bash
# Confirm release was created
gh release view --repo scasplte2/ottochain
```

### Step 2: Verify artifact publication

| Component | Check |
|-----------|-------|
| `ottochain` | JAR attached to GitHub Release |
| `ottochain-sdk` | `npm info @ottochain/sdk version` |
| `ottochain-services` | `docker pull ghcr.io/scasplte2/ottochain-services:vX.Y.Z` |
| `ottochain-explorer` | `docker pull ghcr.io/ottobot-ai/ottochain-explorer:vX.Y.Z` |

### Step 3: Release the next component in order

Repeat Steps 1–2 for each component following the dependency chain:

```
1. ottochain  →  2. ottochain-sdk  →  3. ottochain-services  →  4. ottochain-explorer
```

> **Wait for each artifact to publish** before releasing the next component.  
> Services Docker images can take 3–5 minutes to build and push.

### Step 4: Update versions.yaml

After all components are released, update `versions.yaml` in this repo with the new versions:

```yaml
# versions.yaml
components:
  ottochain: "X.Y.Z"       # Update
  sdk: "X.Y.Z"             # Update
  services: "X.Y.Z"        # Update
  explorer: "X.Y.Z"        # Update
  monitoring: "0.1.0"      # Only update if monitoring changed
```

The `deploy-on-merge.yml` workflow runs automatically when this PR merges, deploying to **scratch** environment.

```bash
# Create the update PR
cd ~/repos/ottochain-deploy
git checkout -b release/vX.Y.Z-ecosystem
# Edit versions.yaml
git commit -m "chore: bump ecosystem to vX.Y.Z"
git push -u origin release/vX.Y.Z-ecosystem
gh pr create --repo ottobot-ai/ottochain-deploy --title "chore: bump ecosystem to vX.Y.Z" \
  --body "## Release vX.Y.Z\n\n- ottochain: ...\n- sdk: ...\n- services: ...\n- explorer: ..."
```

### Step 5: Update COMPATIBILITY.md

```bash
cd ~/repos/ottochain-deploy
scripts/generate-compatibility.sh
git add COMPATIBILITY.md
git commit -m "docs: update compatibility matrix for vX.Y.Z"
git push
```

### Step 6: Verify scratch deployment

After the `versions.yaml` PR merges, verify:

```bash
# Check deploy workflow ran successfully
gh run list --repo ottobot-ai/ottochain-deploy --limit 5

# Verify services health
curl -s http://5.78.121.248:3030/health | jq .
curl -s http://5.78.121.248:3031/health | jq .

# Check cluster state
curl -s http://5.78.90.207:9000/node/info | jq -r .state   # GL0
curl -s http://5.78.107.77:9200/node/info | jq -r .state   # ML0
```

---

## Part 3: Post-Release Checklist

- [ ] All Docker images tagged and pullable
- [ ] `versions.yaml` updated in `ottochain-deploy`
- [ ] `COMPATIBILITY.md` regenerated
- [ ] Scratch environment healthy (monitor: `http://5.78.121.248:3032`)
- [ ] Smoke tests passed (see `smoke-test.yml` workflow)
- [ ] Release notes shared with team (post in Discord #releases or Telegram)

### Notify team

```bash
# Example announcement (adjust version numbers)
echo "🚀 OttoChain v0.8.0 released!
- ottochain: v0.8.0 (DFA state machine, delegated signing)
- sdk: v0.3.0 (delegation helpers, fiber subscription)
- services: v0.4.0 (rejection notifications, metrics)
- explorer: v0.4.0 (rejection history UI)
Deployed to scratch. Monitor: http://5.78.121.248:3032"
```

---

## Part 4: Promoting to Staging/Production

> **Note:** Auto-deploy is only enabled for `scratch`. Staging and production require manual promotion.

### Promote to Staging

```bash
# Trigger promote workflow
gh workflow run promote.yml --repo ottobot-ai/ottochain-deploy \
  -f source_env=scratch \
  -f target_env=staging \
  -f confirm=true
```

Verify staging before promoting to production:
- [ ] All cluster nodes `Ready`
- [ ] Bridge/Indexer healthy
- [ ] Traffic generator producing expected metrics
- [ ] No error spikes in logs

### Promote to Production

```bash
gh workflow run promote.yml --repo ottobot-ai/ottochain-deploy \
  -f source_env=staging \
  -f target_env=production \
  -f confirm=true
```

> Production cluster is TBD (no cluster configured yet in `versions.yaml`). This step will be activated when production infrastructure is provisioned.

---

## Part 5: Rollback Procedure

If a release causes issues, roll back by reverting `versions.yaml` to the previous known-good state.

### Fast rollback (< 5 min)

```bash
# Revert versions.yaml to previous known-good
cd ~/repos/ottochain-deploy
git log versions.yaml --oneline | head -5   # Find last good commit
git checkout <commit-hash> -- versions.yaml
git commit -m "revert: rollback to vX.Y.Z-previous (stability issue)"
git push
# PR merge triggers auto-deploy of old versions
```

### Manual service rollback (if CI is broken)

```bash
# SSH to services host
ssh -i ~/.ssh/hetzner_ottobot root@5.78.121.248

# Pull previous image tag
docker pull ghcr.io/ottobot-ai/ottochain-services:v0.3.5  # previous good tag

# Update docker-compose to use old tag and restart
cd /opt/ottochain-services
# Edit docker-compose.yml image tag
docker compose up -d --no-deps bridge indexer
```

### Metagraph rollback

If the metagraph JAR needs rollback, this requires a **full redeploy** via DEPLOYMENT.md.
> ⚠️ **Warning:** Metagraph rollback wipes chain state if the new version made incompatible state changes. Coordinate with James before rolling back the core metagraph.

---

## Part 6: Hotfix Procedure

For urgent fixes that need to ship without waiting for the normal release-please cycle:

### When to use hotfix
- Critical security vulnerability
- Production down / data loss
- Regression in a recently released feature blocking users

### Hotfix steps

1. **Create a hotfix branch from the release tag:**
   ```bash
   git checkout -b hotfix/v0.3.1 v0.3.0    # branch from release tag
   # Apply minimal fix
   git commit -m "fix: <description>"
   ```

2. **Skip release-please** — manually tag and create release:
   ```bash
   git tag v0.3.1
   git push origin hotfix/v0.3.1 --tags
   
   # Create GitHub release manually
   gh release create v0.3.1 \
     --title "v0.3.1 - Hotfix: <description>" \
     --notes "**Hotfix release** — fixes <issue>. See <PR link>." \
     --repo ottobot-ai/ottochain-services
   ```

3. **Update `versions.yaml`** as per normal release (Step 4 above)

4. **Merge fix back to `develop`** to keep branches in sync:
   ```bash
   git checkout develop
   git merge hotfix/v0.3.1
   git push
   ```

5. **Let release-please pick up the fix** on the next regular release — it will see the tag and incorporate the changelog entry.

---

## Part 7: Breaking Changes

A breaking change is any release where:
- Wire format of DataUpdate or other network messages changes
- Metagraph state shape changes (requires genesis reset on scratch)
- SDK API surface changes in a non-backward-compatible way
- REST API endpoints are removed or their response shapes change

### Breaking change checklist

- [ ] Use `feat!:` commit prefix or add `BREAKING CHANGE:` footer in commit message
- [ ] Update `COMPATIBILITY.md` with the new compatibility row **before** the release
- [ ] Release all affected dependent components in the **same release window**
- [ ] If metagraph state changed incompatibly: plan a scratch environment **genesis reset**
- [ ] Document migration steps in the GitHub Release notes
- [ ] Notify James 24h in advance

### Genesis reset on scratch (breaking metagraph changes only)

```bash
# Deploy new metagraph JARs and run genesis mode
# See DEPLOYMENT.md Part 6 for full procedure

# IMPORTANT: Wipe indexer DB to stay in sync with fresh chain
docker exec postgres psql -U otto -c "
  TRUNCATE fibers, data_updates, snapshots, rejections CASCADE;
"
```

---

## Appendix A: Workflow Reference

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `release-please.yml` | Push to `main` | Opens/updates Release PR, creates tags |
| `version-bump.yml` | Repository dispatch | Creates PR to bump a component in `versions.yaml` |
| `validate-versions.yml` | PR changes `versions.yaml` | Validates compatibility, checks image existence |
| `deploy-on-merge.yml` | Merge to `main` | Deploys to scratch environment |
| `promote.yml` | Manual dispatch | Copies deployment from one env to another |
| `smoke-test.yml` | After deploy | Runs health checks and basic E2E tests |

---

## Appendix B: Useful Commands

```bash
# Check all node states
for ip in 5.78.90.207 5.78.113.25 5.78.107.77; do
  echo "=== Node $ip ==="; 
  curl -s http://$ip:9000/node/info | jq -r '"GL0: " + .state'
  curl -s http://$ip:9200/node/info | jq -r '"ML0: " + .state'
  curl -s http://$ip:9400/node/info | jq -r '"DL1: " + .state'
done

# Check services
curl -s http://5.78.121.248:3030/health | jq .    # Bridge
curl -s http://5.78.121.248:3031/health | jq .    # Indexer
curl -s http://5.78.121.248:4000/health | jq .    # Gateway
curl -u admin:pass http://5.78.121.248:3032/api/status | jq .overall  # Monitor

# Current deployed versions
cat ~/repos/ottochain-deploy/versions.yaml

# Compatibility matrix
cat ~/repos/ottochain-deploy/COMPATIBILITY.md
```

---

## Appendix C: Release Environment Inventory

| Environment | Purpose | Cluster | Auto-deploy |
|-------------|---------|---------|-------------|
| `scratch` | Agent/dev testing | Hetzner (3 nodes) | ✅ On `versions.yaml` merge |
| `staging` | Pre-prod validation | Hetzner | ❌ Manual promote |
| `production` | Live users | TBD | ❌ Manual promote |

**Scratch node IPs:**
- node1: `5.78.90.207` (GL0, CL1, DL1)
- node2: `5.78.113.25` (CL1, DL1)
- node3: `5.78.107.77` (ML0, CL1, DL1)
- services: `5.78.121.248` (Bridge:3030, Indexer:3031, Gateway:4000, Monitor:3032)

SSH access: `ssh -i ~/.ssh/hetzner_ottobot root@<IP>`

---

*See also: [DEPLOYMENT.md](DEPLOYMENT.md) | [COMPATIBILITY.md](COMPATIBILITY.md) | [VERSIONING-MIGRATION.md](VERSIONING-MIGRATION.md)*
