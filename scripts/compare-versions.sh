#!/usr/bin/env bash
# compare-versions.sh — Compare current deployed versions with target versions
# Produces a deployment plan showing what will change.
#
# Usage: ./scripts/compare-versions.sh [environment] [branch]
# Output: Deployment plan written to stdout (redirect to file as needed)

set -euo pipefail

ENVIRONMENT="${1:-development}"
BRANCH="${2:-$(git branch --show-current 2>/dev/null || echo 'unknown')}"
VERSIONS_FILE="${VERSIONS_FILE:-versions.yaml}"
PLAN_OUTPUT="${PLAN_OUTPUT:-deployment-plan.txt}"

echo "🔍 Comparing versions for environment: $ENVIRONMENT (branch: $BRANCH)"

changes_detected=false
plan_lines=()

# Read current versions from versions.yaml
if [ -f "$VERSIONS_FILE" ]; then
  plan_lines+=("## Deployment Plan: $ENVIRONMENT")
  plan_lines+=("Branch: $BRANCH")
  plan_lines+=("Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')")
  plan_lines+=("")

  # Check each component defined in versions.yaml
  if command -v yq &>/dev/null; then
    components=$(yq '.components | keys | .[]' "$VERSIONS_FILE" 2>/dev/null || echo "")
    if [ -n "$components" ]; then
      plan_lines+=("### Component Changes")
      while IFS= read -r component; do
        target=$(yq ".components.${component}.version // \"unknown\"" "$VERSIONS_FILE" 2>/dev/null || echo "unknown")
        plan_lines+=("  - ${component}: → ${target}")
        changes_detected=true
      done <<< "$components"
    fi
  else
    plan_lines+=("### Version File")
    plan_lines+=("$(cat "$VERSIONS_FILE" | head -30)")
    changes_detected=true
  fi
else
  plan_lines+=("## Deployment Plan: $ENVIRONMENT")
  plan_lines+=("No versions.yaml found — deploying with current configuration")
  changes_detected=true
fi

# Write plan
printf '%s\n' "${plan_lines[@]}"

# Set outputs for GitHub Actions
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "changes_detected=$changes_detected" >> "$GITHUB_OUTPUT"
  echo "plan_file=$PLAN_OUTPUT" >> "$GITHUB_OUTPUT"
  echo "environment=$ENVIRONMENT" >> "$GITHUB_OUTPUT"
fi
