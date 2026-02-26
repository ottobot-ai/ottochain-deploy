#!/usr/bin/env bash
# rollback-release.sh — Automated Release Rollback
#
# Rolls back a component to a previous version. Can restore from
# a snapshot file or accept an explicit version to roll back to.
#
# Usage:
#   ./scripts/rollback-release.sh <component> <previous-version>
#   ./scripts/rollback-release.sh --snapshot .release-snapshots/20260219_...yaml
#   ./scripts/rollback-release.sh --list                  # List available snapshots
#
# Examples:
#   # Roll back services to 0.4.0
#   ./scripts/rollback-release.sh services 0.4.0
#
#   # Restore full ecosystem from a snapshot
#   ./scripts/rollback-release.sh --snapshot .release-snapshots/20260219_120000_services_0.4.1_to_0.5.0.yaml
#
#   # List recent rollback points
#   ./scripts/rollback-release.sh --list

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSIONS_FILE="$ROOT_DIR/versions.yaml"
SNAPSHOTS_DIR="$ROOT_DIR/.release-snapshots"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
[[ -t 1 ]] || { RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''; }

info()    { echo -e "${CYAN}ℹ${NC}  $*"; }
success() { echo -e "${GREEN}✓${NC}  $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
error()   { echo -e "${RED}✗${NC}  $*" >&2; }
fatal()   { error "$*"; exit 1; }
header()  { echo -e "\n${BOLD}$*${NC}"; echo "────────────────────────────────────────────"; }

require_cmd() {
  command -v "$1" &>/dev/null || fatal "Required: $1 ($2)"
}

# ── Argument Parsing ─────────────────────────────────────────────────────────
COMPONENT=""
ROLLBACK_VERSION=""
SNAPSHOT_FILE=""
LIST_MODE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)         LIST_MODE=true;        shift ;;
    --snapshot|-s)  SNAPSHOT_FILE="$2";    shift 2 ;;
    --dry-run)      DRY_RUN=true;          shift ;;
    -h|--help)
      grep "^#" "$0" | head -25 | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      if [[ -z "$COMPONENT" ]]; then COMPONENT="$1"
      elif [[ -z "$ROLLBACK_VERSION" ]]; then ROLLBACK_VERSION="$1"
      fi
      shift ;;
  esac
done

require_cmd yq "brew install yq / apt install yq"
require_cmd git "standard system tool"

# ── List Mode ─────────────────────────────────────────────────────────────────
if $LIST_MODE; then
  header "📦 Available Rollback Snapshots"
  if [[ ! -d "$SNAPSHOTS_DIR" ]] || [[ -z "$(ls "$SNAPSHOTS_DIR"/*.yaml 2>/dev/null)" ]]; then
    warn "No snapshots found in $SNAPSHOTS_DIR"
    exit 0
  fi

  printf "%-50s %s\n" "SNAPSHOT" "OPERATION"
  echo "────────────────────────────────────────────────────────────────"
  for f in $(ls -t "$SNAPSHOTS_DIR"/*.yaml 2>/dev/null | head -20); do
    snap_comp=$(yq '.rollback.component' "$f" 2>/dev/null || echo "?")
    snap_from=$(yq '.rollback.from_version' "$f" 2>/dev/null || echo "?")
    snap_to=$(yq '.rollback.restore_version' "$f" 2>/dev/null || echo "?")
    snap_created=$(yq '.rollback.created_at' "$f" 2>/dev/null || echo "?")
    printf "%-50s %s → %s (would restore to %s)\n" "$(basename "$f")" "$snap_comp@$snap_from" "$snap_comp@$snap_to" "$snap_comp@$snap_to"
  done
  echo ""
  info "Use: ./scripts/rollback-release.sh --snapshot <file>"
  exit 0
fi

# ── Snapshot rollback ─────────────────────────────────────────────────────────
if [[ -n "$SNAPSHOT_FILE" ]]; then
  [[ -f "$SNAPSHOT_FILE" ]] || fatal "Snapshot file not found: $SNAPSHOT_FILE"

  COMPONENT=$(yq '.rollback.component' "$SNAPSHOT_FILE")
  ROLLBACK_VERSION=$(yq '.rollback.restore_version' "$SNAPSHOT_FILE")

  header "📦 Rolling back from snapshot"
  info "Component : $COMPONENT"
  info "Restore to: $ROLLBACK_VERSION"
  info "Snapshot  : $(basename "$SNAPSHOT_FILE")"
fi

# ── Validation ────────────────────────────────────────────────────────────────
[[ -n "$COMPONENT" ]]        || fatal "Component required. Use --list to see options."
[[ -n "$ROLLBACK_VERSION" ]] || fatal "Target version required."

current_version=$(yq ".components.$COMPONENT.version" "$VERSIONS_FILE" 2>/dev/null || echo "")
[[ -n "$current_version" && "$current_version" != "null" ]] || \
  fatal "Unknown component: $COMPONENT"

if [[ "$current_version" == "$ROLLBACK_VERSION" ]]; then
  warn "$COMPONENT is already at v$ROLLBACK_VERSION — nothing to do"
  exit 0
fi

header "🔄 Rollback Plan"
echo "  Component    : ${BOLD}$COMPONENT${NC}"
echo "  Current      : ${RED}$current_version${NC}"
echo "  Rolling back : ${GREEN}$ROLLBACK_VERSION${NC}"
$DRY_RUN && echo -e "  ${YELLOW}Mode: DRY RUN — no changes${NC}"
echo ""

if $DRY_RUN; then
  warn "Dry run — no changes made"
  exit 0
fi

# ── Perform rollback ──────────────────────────────────────────────────────────
header "📝 Updating versions.yaml"
yq -i ".components.$COMPONENT.version = \"$ROLLBACK_VERSION\"" "$VERSIONS_FILE"
sed -i "s/^# Last updated:.*/# Last updated: $(date +%Y-%m-%d)/" "$VERSIONS_FILE"
sed -i "s/^# Updated by:.*/# Updated by: rollback-release.sh ($COMPONENT → v$ROLLBACK_VERSION)/" "$VERSIONS_FILE"
success "Rolled back $COMPONENT to $ROLLBACK_VERSION in versions.yaml"

header "📊 Regenerating COMPATIBILITY.md"
if [[ -f "$SCRIPT_DIR/generate-compatibility.sh" ]]; then
  bash "$SCRIPT_DIR/generate-compatibility.sh" && success "COMPATIBILITY.md regenerated"
fi

header "💾 Committing rollback"
cd "$ROOT_DIR"
git add versions.yaml COMPATIBILITY.md 2>/dev/null || true
git diff --cached --quiet || \
  git commit -m "chore: rollback $COMPONENT from v$current_version to v$ROLLBACK_VERSION [ROLLBACK]"
success "Rollback committed"

echo ""
header "✅ Rollback Complete"
success "$COMPONENT restored from $current_version to $ROLLBACK_VERSION"
echo ""
info "Next steps:"
echo "  1. Push this repo: git push origin main (or open a PR)"
echo "  2. CI will deploy the rolled-back version"
echo "  3. Verify: scripts/check-versions.sh"
