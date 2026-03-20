# Compatibility Testing

Real integration testing between OttoChain ecosystem components before deployment.

## Overview

When a PR bumps the `ottochain` (metagraph) version in `versions.yaml`, the
`validate-versions.yml` workflow now does two things:

1. **Semver validation** — checks that versions.yaml structure is valid and
   artifacts exist (existing behaviour, unchanged)

2. **Real integration test** — dispatches `compatibility-check.yml` in
   `ottobot-ai/ottochain-services`, which spins up a full local cluster
   (GL0 + ML0 + DL1) using the proposed metagraph version and runs
   the traffic-generator integration test against `services@main`

The compatibility check is the strongest signal we have: it creates state
machines, activates fibers, and verifies the indexer picks them up.

## Status Check

The `compatibility-dispatch` job in `validate-versions.yml` will:
- **Green** → services@main is compatible with the proposed metagraph version
- **Red** → breaking change detected — merge is blocked until services is updated
- **Skipped** → RELEASE_TOKEN not configured (see setup below)

## Setup: Cross-Repo Auth (RELEASE_TOKEN)

Dispatching `workflow_dispatch` to another repo requires a token with
`actions:write` scope on `ottobot-ai/ottochain-services`.

### Option A: Fine-Grained PAT (quickest)

1. Go to GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens
2. Create a token scoped to **`ottobot-ai/ottochain-services`** with permissions:
   - **Actions** → Read and Write
3. Add the token as a secret named `RELEASE_TOKEN` in `ottobot-ai/ottochain-deploy`
   - Settings → Secrets and variables → Actions → New repository secret

### Option B: GitHub App (preferred for teams)

1. Create a GitHub App owned by the `ottobot-ai` org
2. Grant it `actions:write` on `ottobot-ai/ottochain-services`
3. Install the app on both repos
4. Use the app's installation token as `RELEASE_TOKEN` via the `actions/create-github-app-token` action
   (update the `compatibility-dispatch` job accordingly)

## Scope Decision

The compatibility check covers the **services ↔ metagraph** axis:
- **Services** (`ottobot-ai/ottochain-services`) is tested at `main`
- **Metagraph** is tested at the proposed version in the deploy PR

The **explorer** is not included in the test matrix because explorer
talks only to the services API (not directly to the metagraph), and
services API compatibility is already covered by the traffic-generator test.

## Compatibility Matrix

`compatibility.yaml` in this repo defines semver ranges. It is used by the
existing `validate-versions.yml` semver check and serves as documentation of
intended compatibility bounds. It is **not retired** — the integration test
provides real signal while the semver check provides a fast first gate.

| Role | Tool |
|------|------|
| Fast gate (syntax + ranges) | `validate-versions.yml` semver check |
| Real integration signal | `compatibility-check.yml` in services repo |

## Troubleshooting

**Compatibility check dispatched but no run appears in services:**
- Verify the RELEASE_TOKEN has `actions:write` on `ottochain-services`
- Check the `compatibility-dispatch` job logs for dispatch errors

**Compatibility check times out (50m):**
- The `compatibility-check.yml` run in services has its own 45m timeout
- Check the run directly: https://github.com/ottobot-ai/ottochain-services/actions

**Compatibility check fails with a metagraph bump that should work:**
- Look at the traffic-generator test failure in the services run logs
- The most common cause is a breaking change in the metagraph snapshot format
  or a new required field in the data-l1 HTTP API

**The validate job passes but compatibility check isn't dispatched:**
- The `compatibility-dispatch` job only runs when `metagraph_bumped == 'true'`
- It only fires for `ottochain` version bumps, not `services`/`explorer`/`watchdog`
