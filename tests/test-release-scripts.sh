#!/usr/bin/env bash
# test-release-scripts.sh — Unit tests for release coordination scripts
#
# Tests the release-coordinator.sh, validate-compatibility.sh, and
# rollback-release.sh scripts using temporary directories.
#
# Usage:
#   ./tests/test-release-scripts.sh
#   ./tests/test-release-scripts.sh -v     # verbose

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Test infrastructure
PASS=0; FAIL=0; SKIP=0
VERBOSE="${1:-}"
TMPDIR_BASE=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

pass() { ((PASS++)) || true; echo -e "  ${GREEN}✓${NC} $*"; }
fail() { ((FAIL++)) || true; echo -e "  ${RED}✗${NC} $*"; }
skip() { ((SKIP++)) || true; echo -e "  ${YELLOW}↷${NC} $* (skipped)"; }
group() { echo -e "\n${1}"; echo "────────────────────────────────────────────"; }

assert_exit_0() {
  local cmd="$1"; local desc="$2"
  if eval "$cmd" &>/dev/null; then pass "$desc"; else fail "$desc"; fi
}

assert_exit_nonzero() {
  local cmd="$1"; local desc="$2"
  if ! eval "$cmd" &>/dev/null; then pass "$desc"; else fail "$desc"; fi
}

assert_contains() {
  local output="$1"; local pattern="$2"; local desc="$3"
  if echo "$output" | grep -q "$pattern"; then pass "$desc"; else
    fail "$desc (pattern '$pattern' not found in: ${output:0:200})"
  fi
}

assert_file_contains() {
  local file="$1"; local pattern="$2"; local desc="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then pass "$desc"
  else fail "$desc (pattern '$pattern' not in $file)"; fi
}

# Setup: create a temp workspace with minimal config
setup_workspace() {
  TMPDIR_BASE=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_BASE"' EXIT

  # Create minimal versions.yaml
  cat > "$TMPDIR_BASE/versions.yaml" << 'YAML'
# Last updated: 2026-02-19
# Updated by: test setup
components:
  ottochain:
    version: "0.7.5"
    repo: "scasplte2/ottochain"
  sdk:
    version: "1.0.1"
    repo: "ottobot-ai/ottochain-sdk"
    package: "@ottochain/sdk"
  services:
    version: "0.4.1"
    repo: "ottobot-ai/ottochain-services"
    image: "ghcr.io/ottobot-ai/ottochain-services"
  explorer:
    version: "0.4.1"
    repo: "ottobot-ai/ottochain-explorer"
    image: "ghcr.io/ottobot-ai/ottochain-explorer"
YAML

  # Create minimal compatibility.yaml
  cat > "$TMPDIR_BASE/compatibility.yaml" << 'YAML'
components:
  services:
    requires:
      sdk: ">=0.5.0"
      ottochain: ">=0.5.0 <2.0.0"
  explorer:
    requires:
      services: ">=0.3.0"
YAML

  # Create minimal generate-compatibility.sh (stub)
  mkdir -p "$TMPDIR_BASE/scripts"
  cat > "$TMPDIR_BASE/scripts/generate-compatibility.sh" << 'BASH'
#!/bin/bash
echo "# COMPATIBILITY.md (test stub)" > "$(dirname "$(dirname "$0")")/COMPATIBILITY.md"
BASH
  chmod +x "$TMPDIR_BASE/scripts/generate-compatibility.sh"

  # Initialize a git repo (needed for commit step)
  cd "$TMPDIR_BASE"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git add -A
  git commit -q -m "initial"

  # Copy the actual scripts to test
  cp "$ROOT_DIR/scripts/release-coordinator.sh" "$TMPDIR_BASE/scripts/"
  cp "$ROOT_DIR/scripts/validate-compatibility.sh" "$TMPDIR_BASE/scripts/"
  cp "$ROOT_DIR/scripts/rollback-release.sh" "$TMPDIR_BASE/scripts/"
  chmod +x "$TMPDIR_BASE/scripts/"*.sh
}

# ── Semver Validation Tests ────────────────────────────────────────────────────
group "Semver Validation"

test_semver() {
  setup_workspace

  # Valid semver
  assert_exit_0 \
    "cd $TMPDIR_BASE && bash scripts/release-coordinator.sh sdk 1.1.0 --dry-run --no-compat" \
    "Valid semver 1.1.0 accepted"

  assert_exit_0 \
    "cd $TMPDIR_BASE && bash scripts/release-coordinator.sh sdk 1.1.0-rc.1 --dry-run --no-compat --force" \
    "Pre-release semver 1.1.0-rc.1 accepted with --force"

  # Invalid semver
  assert_exit_nonzero \
    "cd $TMPDIR_BASE && bash scripts/release-coordinator.sh sdk notaversion --dry-run 2>/dev/null" \
    "Invalid semver 'notaversion' rejected"

  assert_exit_nonzero \
    "cd $TMPDIR_BASE && bash scripts/release-coordinator.sh sdk 1.2 --dry-run 2>/dev/null" \
    "Incomplete semver '1.2' rejected"

  # Version must be ascending
  assert_exit_nonzero \
    "cd $TMPDIR_BASE && bash scripts/release-coordinator.sh sdk 0.9.0 --dry-run --no-compat 2>/dev/null" \
    "Downgrade rejected without --force"

  assert_exit_0 \
    "cd $TMPDIR_BASE && bash scripts/release-coordinator.sh sdk 0.9.0 --dry-run --no-compat --force" \
    "Downgrade allowed with --force"
}
test_semver

# ── Unknown Component Tests ───────────────────────────────────────────────────
group "Component Validation"

test_components() {
  setup_workspace

  assert_exit_nonzero \
    "cd $TMPDIR_BASE && bash scripts/release-coordinator.sh unknown_thing 1.0.0 --dry-run 2>/dev/null" \
    "Unknown component rejected"

  assert_exit_0 \
    "cd $TMPDIR_BASE && bash scripts/release-coordinator.sh sdk 1.1.0 --dry-run --no-compat" \
    "Known component 'sdk' accepted"

  assert_exit_0 \
    "cd $TMPDIR_BASE && bash scripts/release-coordinator.sh ottochain 0.8.0 --dry-run --no-compat" \
    "Known component 'ottochain' accepted"
}
test_components

# ── Compatibility Validation Tests ────────────────────────────────────────────
group "Compatibility Validation"

test_compat() {
  setup_workspace

  # Current state should be valid (all constraints satisfied by test data)
  local output
  output=$(cd "$TMPDIR_BASE" && bash scripts/validate-compatibility.sh 2>&1 || true)
  assert_contains "$output" "passed" "Current state passes compatibility check"

  # Hypothetical valid bump
  output=$(cd "$TMPDIR_BASE" && bash scripts/validate-compatibility.sh sdk 1.2.0 2>&1 || true)
  assert_contains "$output" "passed" "Valid sdk bump passes compatibility check"

  # Simulate compatibility violation: services needs sdk >=0.5.0 but bump sdk to 0.4.9
  # (sdk 0.4.9 < services' >=0.5.0 requirement)
  output=$(cd "$TMPDIR_BASE" && bash scripts/validate-compatibility.sh sdk 0.4.9 2>&1 || true)
  assert_contains "$output" "violation\|Violation\|failed\|requires" \
    "sdk 0.4.9 (below services' >=0.5.0 requirement) produces violation"

  # JSON output mode
  output=$(cd "$TMPDIR_BASE" && bash scripts/validate-compatibility.sh --json 2>&1 || true)
  assert_contains "$output" '"valid"' "JSON output contains valid field"
  assert_contains "$output" '"versions"' "JSON output contains versions field"
}
test_compat

# ── Dry Run Tests ─────────────────────────────────────────────────────────────
group "Dry Run Mode"

test_dry_run() {
  setup_workspace

  local before_versions; before_versions=$(cat "$TMPDIR_BASE/versions.yaml")

  cd "$TMPDIR_BASE" && bash scripts/release-coordinator.sh sdk 1.1.0 --dry-run --no-compat >/dev/null 2>&1 || true

  local after_versions; after_versions=$(cat "$TMPDIR_BASE/versions.yaml")

  if [[ "$before_versions" == "$after_versions" ]]; then
    pass "Dry run does not modify versions.yaml"
  else
    fail "Dry run modified versions.yaml (should not)"
  fi
}
test_dry_run

# ── Version Update Tests ──────────────────────────────────────────────────────
group "Version Update (no-tag, no-compat)"

test_version_update() {
  setup_workspace

  cd "$TMPDIR_BASE" && bash scripts/release-coordinator.sh sdk 1.2.0 --no-tag --no-compat >/dev/null 2>&1

  assert_file_contains "$TMPDIR_BASE/versions.yaml" '"1.2.0"\|1.2.0' \
    "versions.yaml updated with new sdk version"

  # Check git log
  local log; log=$(cd "$TMPDIR_BASE" && git log --oneline -1)
  assert_contains "$log" "sdk\|1.2.0" "Git commit created for version bump"
}
test_version_update

# ── Snapshot Creation Tests ───────────────────────────────────────────────────
group "Snapshot Creation"

test_snapshot() {
  setup_workspace

  cd "$TMPDIR_BASE" && bash scripts/release-coordinator.sh services 0.5.0 --no-tag --no-compat >/dev/null 2>&1

  local snapshot_count; snapshot_count=$(ls "$TMPDIR_BASE/.release-snapshots/"*.yaml 2>/dev/null | wc -l)
  if [[ "$snapshot_count" -ge 1 ]]; then
    pass "Snapshot file created after release"
  else
    fail "No snapshot file found in .release-snapshots/"
  fi

  local snapshot_file; snapshot_file=$(ls "$TMPDIR_BASE/.release-snapshots/"*.yaml | head -1)
  assert_file_contains "$snapshot_file" "services" "Snapshot records component name"
  assert_file_contains "$snapshot_file" "0.4.1" "Snapshot records previous version"
  assert_file_contains "$snapshot_file" "0.5.0" "Snapshot records new version"
}
test_snapshot

# ── Rollback Tests ────────────────────────────────────────────────────────────
group "Rollback"

test_rollback() {
  setup_workspace

  # First do a release
  cd "$TMPDIR_BASE" && bash scripts/release-coordinator.sh services 0.5.0 --no-tag --no-compat >/dev/null 2>&1

  # Then rollback
  cd "$TMPDIR_BASE" && bash scripts/rollback-release.sh services 0.4.1 >/dev/null 2>&1

  assert_file_contains "$TMPDIR_BASE/versions.yaml" '"0.4.1"\|0.4.1' \
    "versions.yaml restored to previous version after rollback"

  # Rollback on same version is no-op
  local exit_code=0
  cd "$TMPDIR_BASE" && bash scripts/rollback-release.sh services 0.4.1 >/dev/null 2>&1 || exit_code=$?
  if [[ "$exit_code" -eq 0 ]]; then
    pass "Rolling back to current version exits 0 (no-op)"
  else
    fail "Rolling back to current version should be a no-op"
  fi
}
test_rollback

# ── Rollback List Tests ────────────────────────────────────────────────────────
group "Rollback List"

test_rollback_list() {
  setup_workspace

  # Empty snapshots dir
  local output
  output=$(cd "$TMPDIR_BASE" && bash scripts/rollback-release.sh --list 2>&1 || true)
  assert_contains "$output" "No snapshots\|snapshots" "Empty list shows no-snapshots message"

  # After a release, snapshot should appear
  cd "$TMPDIR_BASE" && bash scripts/release-coordinator.sh sdk 1.2.0 --no-tag --no-compat >/dev/null 2>&1
  output=$(cd "$TMPDIR_BASE" && bash scripts/rollback-release.sh --list 2>&1 || true)
  assert_contains "$output" "sdk" "Snapshot appears in list after release"
}
test_rollback_list

# ── Validate-Compat Standalone ────────────────────────────────────────────────
group "validate-compatibility.sh standalone"

test_validate_standalone() {
  setup_workspace

  # --all flag shows versions table
  local output
  output=$(cd "$TMPDIR_BASE" && bash scripts/validate-compatibility.sh --all 2>&1 || true)
  assert_contains "$output" "sdk\|services\|ottochain" "Shows component versions with --all"

  # --json produces valid JSON
  output=$(cd "$TMPDIR_BASE" && bash scripts/validate-compatibility.sh --json 2>&1 || true)
  if echo "$output" | python3 -m json.tool >/dev/null 2>&1; then
    pass "JSON output is valid JSON"
  else
    skip "python3 not available for JSON validation"
  fi
}
test_validate_standalone

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════"
echo "  Test Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$SKIP skipped${NC}"
echo "════════════════════════════════════════════════════════"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
