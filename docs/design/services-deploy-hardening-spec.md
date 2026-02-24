# Services Deployment Hardening — TDD Specification

**Card**: 🐳 CI: Test and fix services Docker release workflow to ghcr.io  
**Trello**: `69962fdabe9698398485d1b1`  
**Repo**: `ottobot-ai/ottochain-deploy`  
**Branch**: `feat/services-deploy-hardening`  
**Assigned**: @work  
**Size**: S (~1h, all changes in single file)  
**Status**: Spec ready — implement without waiting for further approval

---

## Summary

Four concrete hardening changes to `.github/workflows/deploy-services.yml`.  
**No changes needed in `ottochain-services` — `release.yml` there is already correct.**

Research audit (2026-02-23) confirmed `release.yml` is publishing images correctly  
(`ghcr.io/ottobot-ai/ottochain-services:v0.4.1` verified ✅). All gaps are in `deploy-services.yml`.

---

## Fix A: Add GHCR Login Before `docker compose pull`

### Problem
The "Deploy stack" step calls `docker compose pull` with no prior GHCR authentication.  
Currently works because the package is public. If visibility ever changes, deploys silently fail.

### Fix
Add a step using the existing `docker-login-pull` composite action BEFORE "Deploy stack":

```yaml
- name: GHCR login on services server
  uses: ./.github/actions/docker-login-pull
  with:
    github_token: ${{ secrets.DEPLOY_REPO_TOKEN }}
    image: ghcr.io/ottobot-ai/ottochain-services
    hosts: services
    pull: 'false'
```

**Insert after**: `Setup SSH` step  
**Insert before**: `Prepare remote directory` step  
**Token**: `secrets.DEPLOY_REPO_TOKEN` — already exists in repo secrets  
**`pull: 'false'`** — login only, no pull here (compose pull handles it)

---

## Fix B: Health Check Must Fail the Workflow on Errors

### Problem
The "Health check" step currently prints `⚠️ bridge: HTTP 000` but exits 0 — a broken deploy passes CI silently.

### Fix
Replace the health check step body with fail-on-critical logic:

```yaml
- name: Health check
  run: |
    echo "Waiting for services to start..."
    sleep 30

    echo "Checking services health..."
    FAILED=0

    for service in gateway bridge indexer monitor; do
      case $service in
        gateway) port=4000 ;; bridge) port=3030 ;; indexer) port=3031 ;; monitor) port=3032 ;;
      esac
      status=$(ssh services "curl -sf -o /dev/null -w '%{http_code}' http://localhost:$port/health" || echo "000")
      if [ "$status" = "200" ]; then
        echo "✅ $service: healthy"
      else
        echo "⚠️ $service: HTTP $status"
        # Hard-fail on critical services; warn-only on indexer (Prisma migrations are slow)
        if [ "$service" = "gateway" ] || [ "$service" = "bridge" ]; then
          FAILED=1
        fi
      fi
    done

    # Check explorer
    explorer=$(ssh services "curl -sf -o /dev/null -w '%{http_code}' http://localhost:8081" || echo "000")
    if [ "$explorer" = "200" ]; then
      echo "✅ explorer: healthy"
    else
      echo "⚠️ explorer: HTTP $explorer"
    fi

    if [ $FAILED -eq 1 ]; then
      echo "❌ Critical services unhealthy — deploy failed"
      exit 1
    fi
    echo "✅ All critical services healthy"
```

**Key changes from current**:
- `sleep 30` (was 15) — give services adequate startup time  
- `FAILED=0` + `FAILED=1` tracking
- Hard-fail (`exit 1`) if `gateway` or `bridge` are not 200
- `indexer` and `monitor` are warn-only (indexer runs Prisma migrations on startup — variable time)

---

## Fix C: Replace `wget` with `curl` in docker-compose Healthchecks

### Problem
All four OttoChain service containers use `CMD wget -q --spider` for healthchecks.  
Node.js Docker images don't ship with `wget` — healthchecks always return `unhealthy`  
even when services are functioning correctly. `docker compose ps` shows all containers  
as `unhealthy`, causing confusion during debugging.

### Fix
In the "Write docker-compose.yml" step, replace healthcheck test for all 4 OttoChain services:

```yaml
# BEFORE (in all 4 service healthcheck blocks: gateway, bridge, indexer, monitor)
healthcheck:
  test: ["CMD", "wget", "-q", "--spider", "http://localhost:PORT/health"]
  interval: 30s
  timeout: 10s
  retries: 3

# AFTER
healthcheck:
  test: ["CMD-SHELL", "curl -sf http://localhost:PORT/health || exit 1"]
  interval: 30s
  timeout: 10s
  retries: 3
```

Apply to: `gateway` (4000), `bridge` (3030), `indexer` (3031), `monitor` (3032).  
**Do NOT change**: `postgres` (uses `pg_isready`), `redis` (uses `redis-cli ping`), `explorer` (wget works — nginx image has it).

**Note**: Use `CMD-SHELL` (not `CMD`) so the shell expands `||`. `CMD-SHELL` runs via `/bin/sh -c`.

---

## Fix D: Enable Multi-DL1 Fan-Out in Services Environment

### Problem
The "Write .env" step sets only `METAGRAPH_DL1_URL=http://${METAGRAPH_IP}:9400` (single DL1 node).  
The bridge already supports comma-separated `METAGRAPH_DL1_URLS` with automatic fan-out  
(added in PR #136 — `getDl1Urls()` with backward-compatible fallback).  
All three node IPs are already available as secrets in this repo.

### Fix A: Add `METAGRAPH_DL1_URLS` to the .env block

In the "Write .env" step, add after existing DL1_URL line:

```bash
NODE1_IP="${{ secrets.HETZNER_NODE1_IP }}"
NODE2_IP="${{ secrets.HETZNER_NODE2_IP }}"
NODE3_IP="${{ secrets.HETZNER_NODE3_IP }}"
```

And in the ENVFILE heredoc:
```
# Multi-node DL1 fan-out (PR #136 feature)
METAGRAPH_DL1_URLS=http://${NODE1_IP}:9400,http://${NODE2_IP}:9400,http://${NODE3_IP}:9400
```

Keep `METAGRAPH_DL1_URL` (singular) as-is — the bridge falls back to it if `DL1_URLS` is not set, but having both is fine.

### Fix B: Add `METAGRAPH_DL1_URLS` to docker-compose service env blocks

In the `docker-compose.yml` heredoc, add to each service that currently has `METAGRAPH_DL1_URL`:

```yaml
environment:
  - METAGRAPH_DL1_URL=${METAGRAPH_DL1_URL}
  - METAGRAPH_DL1_URLS=${METAGRAPH_DL1_URLS}  # ADD THIS LINE
```

Apply to: `gateway`, `bridge`, `indexer`, `monitor`, `traffic-gen`.

---

## Acceptance Criteria (All must pass before PR merged)

| # | Criterion | How to Verify |
|---|-----------|---------------|
| 1 | GHCR login step added before deploy | Review YAML diff — `docker-login-pull` action called with `hosts: services` |
| 2 | Health check exits 1 if gateway/bridge returns non-200 | Run workflow, manually kill bridge container, verify step fails |
| 3 | Health check sleep is 30s (not 15s) | Review YAML diff |
| 4 | `gateway`, `bridge`, `indexer`, `monitor` healthchecks use `curl` | Review YAML diff — `CMD-SHELL curl -sf ... || exit 1` |
| 5 | `METAGRAPH_DL1_URLS` written to .env with 3 node IPs | Review YAML diff — NODE1/2/3 variables used |
| 6 | `METAGRAPH_DL1_URLS` passed to all 5 services in docker-compose env | Review YAML diff |
| 7 | Full deploy workflow succeeds end-to-end | Trigger `workflow_dispatch` after PR merge |
| 8 | `docker compose ps` shows all services as `healthy` (not `unhealthy`) | SSH to services, run `docker compose ps` |

---

## Test Cases for PR Review Checklist

Since this is a GitHub Actions YAML change (not testable with unit tests), verification is done manually during PR review + post-merge. Use this checklist:

**Pre-merge (static review)**:
- [ ] `docker-login-pull` action step present with `hosts: services`, `pull: 'false'`
- [ ] Health check has `FAILED=0` + `FAILED=1` logic + `exit 1` at end
- [ ] Health check sleep changed from 15 to 30
- [ ] All 4 service healthchecks changed from `wget` to `CMD-SHELL curl -sf ... || exit 1`
- [ ] `METAGRAPH_DL1_URLS` present in .env heredoc using NODE1/2/3 secrets
- [ ] `METAGRAPH_DL1_URLS` present in all 5 service env blocks in docker-compose heredoc

**Post-merge (trigger workflow)**:
- [ ] `workflow_dispatch` run completes green
- [ ] "GHCR login on services server" step shows "✅ GHCR login complete"
- [ ] "Health check" step shows "✅ All critical services healthy"
- [ ] `ssh services docker compose ps` shows all containers as `healthy`
- [ ] Bridge `/health` endpoint responds 200 from outside (confirm multi-DL1 active via bridge logs)

---

## Files Changed

```
ottobot-ai/ottochain-deploy
└── .github/workflows/deploy-services.yml    ← ONLY FILE CHANGED
```

No changes to:
- `ottochain-services/release.yml` ← already correct ✅
- Any metagraph workflows ← unrelated
- Any secrets ← `DEPLOY_REPO_TOKEN`, `HETZNER_NODE{1,2,3}_IP` already exist

---

## Implementation Notes for @work

1. **All four fixes go in a single PR** — they're all changes to one file
2. **Keep heredoc whitespace carefully** — the docker-compose.yml heredoc is indent-sensitive. Test by `cat` the deployed file and checking YAML validity
3. **DEPLOY_REPO_TOKEN scope**: confirm it has `read:packages` scope (needed for `docker login ghcr.io`). It's used in `deploy-metagraph.yml` for same purpose — should be fine
4. **docker-login-pull `hosts` input**: uses space-separated SSH aliases from `~/.ssh/config`. `services` is the services server alias, already configured in `setup-ssh` action
5. **PR target**: `ottobot-ai/ottochain-deploy` main branch (James to review + merge)
