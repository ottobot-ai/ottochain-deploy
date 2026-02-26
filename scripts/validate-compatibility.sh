#!/usr/bin/env bash
# validate-compatibility.sh — Cross-Repo Dependency Validation
#
# Validates that current versions in versions.yaml satisfy all
# cross-repo dependency rules defined in compatibility.yaml.
# Can also validate a hypothetical version bump before applying it.
#
# Usage:
#   ./scripts/validate-compatibility.sh                         # Check current state
#   ./scripts/validate-compatibility.sh sdk 1.1.0               # Check after bumping sdk
#   ./scripts/validate-compatibility.sh --all                   # Full matrix report
#   ./scripts/validate-compatibility.sh --json                  # JSON output for CI
#
# Exit codes:
#   0 — All checks pass
#   1 — One or more violations found
#   2 — Script/config error
#
# Examples (CI):
#   # In GitHub Actions:
#   ./scripts/validate-compatibility.sh --json > compat-report.json
#   cat compat-report.json | jq '.valid'

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSIONS_FILE="$ROOT_DIR/versions.yaml"
COMPAT_FILE="$ROOT_DIR/compatibility.yaml"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
# Disable colors in non-interactive mode
[[ -t 1 ]] || { RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''; }

info()    { echo -e "${CYAN}ℹ${NC}  $*"; }
success() { echo -e "${GREEN}✓${NC}  $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
error()   { echo -e "${RED}✗${NC}  $*"; }

# ── Argument Parsing ─────────────────────────────────────────────────────────
HYPOTHETICAL_COMPONENT=""
HYPOTHETICAL_VERSION=""
SHOW_ALL=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)   SHOW_ALL=true;   shift ;;
    --json)  JSON_OUTPUT=true; shift ;;
    -h|--help)
      grep "^#" "$0" | head -30 | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      if [[ -z "$HYPOTHETICAL_COMPONENT" ]]; then HYPOTHETICAL_COMPONENT="$1"
      elif [[ -z "$HYPOTHETICAL_VERSION" ]]; then HYPOTHETICAL_VERSION="$1"
      fi
      shift ;;
  esac
done

require_cmd() {
  command -v "$1" &>/dev/null || { echo "Required: $1 ($2)" >&2; exit 2; }
}
require_cmd yq "brew install yq / apt install yq"

# ── Version comparison ───────────────────────────────────────────────────────
semver_numeric() {
  local ver="${1%%-*}"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$ver"
  echo $(( major * 1000000 + minor * 1000 + patch ))
}

# Check if $1 satisfies semver range in $2
# Supports: >=X.Y.Z, <X.Y.Z, >=X.Y.Z <A.B.C, >=X.Y.Z
satisfies_range() {
  local version="$1"
  local range="$2"
  local ver_num; ver_num=$(semver_numeric "$version")
  local ok=true

  local ge_re='>=([0-9]+\.[0-9]+\.[0-9]+)'
  local lt_re='<([0-9]+\.[0-9]+\.[0-9]+)'
  if [[ "$range" =~ $ge_re ]]; then
    local min; min=$(semver_numeric "${BASH_REMATCH[1]}")
    [[ "$ver_num" -ge "$min" ]] || ok=false
  fi
  if [[ "$range" =~ $lt_re ]]; then
    local max; max=$(semver_numeric "${BASH_REMATCH[1]}")
    [[ "$ver_num" -lt "$max" ]] || ok=false
  fi
  $ok
}

# ── Load versions ────────────────────────────────────────────────────────────
declare -A VERSIONS=()
while IFS= read -r comp; do
  v=$(yq ".components.$comp.version" "$VERSIONS_FILE" 2>/dev/null || echo "")
  [[ -n "$v" && "$v" != "null" ]] && VERSIONS[$comp]="$v"
done < <(yq '.components | keys | .[]' "$VERSIONS_FILE" 2>/dev/null)

# Apply hypothetical override
if [[ -n "$HYPOTHETICAL_COMPONENT" && -n "$HYPOTHETICAL_VERSION" ]]; then
  VERSIONS[$HYPOTHETICAL_COMPONENT]="$HYPOTHETICAL_VERSION"
  info "Hypothetical: $HYPOTHETICAL_COMPONENT = $HYPOTHETICAL_VERSION"
fi

# ── Check compatibility rules ─────────────────────────────────────────────────
violations=()
checks_passed=0

if [[ ! -f "$COMPAT_FILE" ]]; then
  warn "No compatibility.yaml found — nothing to validate"
  exit 0
fi

while IFS= read -r dependent; do
  while IFS= read -r dep_name; do
    local_range=$(yq ".components.$dependent.requires.$dep_name" "$COMPAT_FILE" 2>/dev/null || true)
    [[ -z "$local_range" || "$local_range" == "null" ]] && continue

    dep_version="${VERSIONS[$dep_name]:-}"
    if [[ -z "$dep_version" ]]; then
      warn "$dependent requires $dep_name but $dep_name version is not known"
      continue
    fi

    dependent_version="${VERSIONS[$dependent]:-}"

    if satisfies_range "$dep_version" "$local_range"; then
      success "$dependent@${dependent_version:-?} → $dep_name@$dep_version (${local_range})"
      ((checks_passed++)) || true
    else
      error "$dependent@${dependent_version:-?} requires $dep_name $local_range (current: $dep_version)"
      violations+=("$dependent requires $dep_name $local_range but found $dep_version")
    fi
  done < <(yq ".components.$dependent.requires | keys | .[]" "$COMPAT_FILE" 2>/dev/null || true)
done < <(yq '.components | keys | .[]' "$COMPAT_FILE" 2>/dev/null || true)

# ── Version report ────────────────────────────────────────────────────────────
if $SHOW_ALL; then
  echo ""
  echo -e "${BOLD}Current Component Versions${NC}"
  echo "────────────────────────────────────────────"
  for comp in $(echo "${!VERSIONS[@]}" | tr ' ' '\n' | sort); do
    printf "  %-20s %s\n" "$comp" "${VERSIONS[$comp]}"
  done
fi

# ── JSON output ───────────────────────────────────────────────────────────────
if $JSON_OUTPUT; then
  valid="true"
  [[ ${#violations[@]} -gt 0 ]] && valid="false"

  echo "{"
  echo "  \"valid\": $valid,"
  echo "  \"checks_passed\": $checks_passed,"
  echo "  \"violations\": ["
  for i in "${!violations[@]}"; do
    comma=","
    [[ $i -eq $((${#violations[@]}-1)) ]] && comma=""
    echo "    \"${violations[$i]}\"$comma"
  done
  echo "  ],"
  echo "  \"versions\": {"
  first=true
  for comp in $(echo "${!VERSIONS[@]}" | tr ' ' '\n' | sort); do
    $first || echo ","
    printf "    \"%s\": \"%s\"" "$comp" "${VERSIONS[$comp]}"
    first=false
  done
  echo ""
  echo "  }"
  echo "}"
fi

# ── Final result ──────────────────────────────────────────────────────────────
if [[ ${#violations[@]} -gt 0 ]]; then
  echo ""
  error "${#violations[@]} compatibility violation(s) found — release blocked"
  exit 1
fi

if ! $JSON_OUTPUT; then
  echo ""
  success "All $checks_passed compatibility checks passed"
fi

exit 0
