#!/usr/bin/env bash
# release-coordinator.sh — OttoChain Cross-Repo Release Orchestration
#
# Coordinates version bumps across the OttoChain ecosystem:
#   - Validates semver and cross-repo compatibility
#   - Updates versions.yaml (single source of truth)
#   - Snapshots current state for rollback
#   - Regenerates COMPATIBILITY.md
#   - Optionally creates git tags in component repos
#
# Usage:
#   ./scripts/release-coordinator.sh <component> <version> [OPTIONS]
#
# Components:
#   ottochain   — Core Scala metagraph (scasplte2/ottochain)
#   sdk         — TypeScript SDK (ottobot-ai/ottochain-sdk)
#   services    — Backend services (ottobot-ai/ottochain-services)
#   explorer    — Explorer UI (ottobot-ai/ottochain-explorer)
#   monitoring  — Monitoring configs (ottobot-ai/ottochain-monitoring)
#
# Options:
#   --dry-run      Validate and report without making changes
#   --no-tag       Skip creating git tag in component repo
#   --no-compat    Skip compatibility validation
#   --force        Override semver ordering check (e.g., for pre-release)
#   --env ENV      Target environment: scratch|staging|production (default: scratch)
#   --message MSG  Release message for commit/tag annotation
#
# Examples:
#   # Bump SDK to 1.1.0 (dry run first)
#   ./scripts/release-coordinator.sh sdk 1.1.0 --dry-run
#   ./scripts/release-coordinator.sh sdk 1.1.0
#
#   # Bump services with a message
#   ./scripts/release-coordinator.sh services 0.5.0 --message "Add delegation support"
#
#   # Major bump with force (skip semver ordering check)
#   ./scripts/release-coordinator.sh ottochain 1.0.0 --force
#
# See also: scripts/rollback-release.sh, scripts/validate-compatibility.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSIONS_FILE="$ROOT_DIR/versions.yaml"
COMPAT_FILE="$ROOT_DIR/compatibility.yaml"
SNAPSHOTS_DIR="$ROOT_DIR/.release-snapshots"

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}ℹ${NC}  $*"; }
success() { echo -e "${GREEN}✓${NC}  $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
error()   { echo -e "${RED}✗${NC}  $*" >&2; }
fatal()   { error "$*"; exit 1; }
header()  { echo -e "\n${BOLD}$*${NC}"; echo "────────────────────────────────────────────"; }

# ── Argument Parsing ─────────────────────────────────────────────────────────
COMPONENT=""
NEW_VERSION=""
DRY_RUN=false
NO_TAG=false
NO_COMPAT=false
FORCE=false
ENV_TARGET="scratch"
RELEASE_MSG=""

usage() {
  grep "^#" "$0" | head -50 | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)     usage ;;
    --dry-run)     DRY_RUN=true;   shift ;;
    --no-tag)      NO_TAG=true;    shift ;;
    --no-compat)   NO_COMPAT=true; shift ;;
    --force)       FORCE=true;     shift ;;
    --env)         ENV_TARGET="$2"; shift 2 ;;
    --message|-m)  RELEASE_MSG="$2"; shift 2 ;;
    *)
      if [[ -z "$COMPONENT" ]]; then COMPONENT="$1"
      elif [[ -z "$NEW_VERSION" ]]; then NEW_VERSION="$1"
      else fatal "Unexpected argument: $1"; fi
      shift ;;
  esac
done

[[ -n "$COMPONENT" ]] || fatal "Component name required. Run with --help for usage."
[[ -n "$NEW_VERSION" ]] || fatal "Version required. Run with --help for usage."

# ── Dependency Checks ────────────────────────────────────────────────────────
require_cmd() {
  command -v "$1" &>/dev/null || fatal "Required tool not found: $1 (install with: $2)"
}
require_cmd yq  "brew install yq / apt install yq"
require_cmd git "standard system tool"
require_cmd gh  "brew install gh / apt install gh"

# ── Semver Helpers ───────────────────────────────────────────────────────────
semver_valid() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$ ]]
}

semver_numeric() {
  # Convert x.y.z to comparable integer: x*1000000 + y*1000 + z
  local ver="${1%%-*}"  # strip pre-release
  local major minor patch
  IFS='.' read -r major minor patch <<< "$ver"
  echo $(( major * 1000000 + minor * 1000 + patch ))
}

semver_gt() {
  [[ $(semver_numeric "$1") -gt $(semver_numeric "$2") ]]
}

# ── versions.yaml Helpers ────────────────────────────────────────────────────
get_current_version() {
  yq ".components.$1.version" "$VERSIONS_FILE" 2>/dev/null || echo ""
}

get_component_repo() {
  yq ".components.$1.repo" "$VERSIONS_FILE" 2>/dev/null || echo ""
}

get_all_components() {
  yq '.components | keys | .[]' "$VERSIONS_FILE" 2>/dev/null
}

# ── Compatibility Validation ─────────────────────────────────────────────────
validate_compatibility() {
  local component="$1"
  local new_version="$2"

  info "Validating cross-repo compatibility..."

  # Read current versions, temporarily override for the component being updated
  declare -A versions=()
  while IFS= read -r comp; do
    versions[$comp]=$(get_current_version "$comp")
  done < <(get_all_components)
  versions[$component]="$new_version"

  local ok=true

  # Check if compatibility.yaml exists (optional validation file)
  if [[ ! -f "$COMPAT_FILE" ]]; then
    warn "No compatibility.yaml found — skipping compatibility rules check"
    return 0
  fi

  # Check dependency requirements from compatibility.yaml
  while IFS= read -r dependent; do
    while IFS= read -r dep_name; do
      local required_range
      required_range=$(yq ".components.$dependent.requires.$dep_name" "$COMPAT_FILE" 2>/dev/null || true)
      if [[ -z "$required_range" || "$required_range" == "null" ]]; then continue; fi

      local dep_version="${versions[$dep_name]:-}"
      if [[ -z "$dep_version" ]]; then continue; fi

      # Parse the range: >=X.Y.Z <A.B.C or >=X.Y.Z
      local min_ver="" max_ver=""
      local ge_re='>=([0-9]+\.[0-9]+\.[0-9]+)'
      local lt_re='<([0-9]+\.[0-9]+\.[0-9]+)'
      if [[ "$required_range" =~ $ge_re ]]; then
        min_ver="${BASH_REMATCH[1]}"
      fi
      if [[ "$required_range" =~ $lt_re ]]; then
        max_ver="${BASH_REMATCH[1]}"
      fi

      local dep_num; dep_num=$(semver_numeric "$dep_version")
      local violation=false

      if [[ -n "$min_ver" ]] && [[ "$dep_num" -lt $(semver_numeric "$min_ver") ]]; then
        violation=true
      fi
      if [[ -n "$max_ver" ]] && [[ "$dep_num" -ge $(semver_numeric "$max_ver") ]]; then
        violation=true
      fi

      if $violation; then
        error "Compatibility violation: $dependent requires $dep_name $required_range (current: $dep_version)"
        ok=false
      else
        success "$dependent → $dep_name@$dep_version satisfies $required_range"
      fi
    done < <(yq ".components.$dependent.requires | keys | .[]" "$COMPAT_FILE" 2>/dev/null || true)
  done < <(yq '.components | keys | .[]' "$COMPAT_FILE" 2>/dev/null || true)

  $ok || return 1
  success "All compatibility rules satisfied"
}

# ── Snapshot (for rollback) ──────────────────────────────────────────────────
create_snapshot() {
  local component="$1"
  local old_version="$2"
  local new_version="$3"

  mkdir -p "$SNAPSHOTS_DIR"
  local snapshot_file="$SNAPSHOTS_DIR/$(date +%Y%m%d_%H%M%S)_${component}_${old_version}_to_${new_version}.yaml"

  cat > "$snapshot_file" << EOF
# Release snapshot — generated by release-coordinator.sh
# Created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Component: $component
# From: $old_version
# To: $new_version
# Environment: $ENV_TARGET

rollback:
  component: "$component"
  restore_version: "$old_version"
  from_version: "$new_version"
  created_at: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Full versions state snapshot (for manual restore if needed)
EOF

  echo "$snapshot_file"
}

# ── Update versions.yaml ─────────────────────────────────────────────────────
update_versions_file() {
  local component="$1"
  local new_version="$2"

  yq -i ".components.$component.version = \"$new_version\"" "$VERSIONS_FILE"
  yq -i ".\"# Last updated\" = \"$(date +%Y-%m-%d)\"" "$VERSIONS_FILE" 2>/dev/null || true

  # Update the Last updated comment via sed (yq doesn't preserve comments)
  sed -i "s/^# Last updated:.*/# Last updated: $(date +%Y-%m-%d)/" "$VERSIONS_FILE"
  sed -i "s/^# Updated by:.*/# Updated by: release-coordinator.sh ($component → v$new_version)/" "$VERSIONS_FILE"
}

# ── Create git tag ───────────────────────────────────────────────────────────
create_git_tag() {
  local component="$1"
  local version="$2"
  local repo; repo=$(get_component_repo "$component")

  if [[ -z "$repo" || "$repo" == "null" ]]; then
    warn "No repo defined for component $component — skipping tag"
    return 0
  fi

  local tag="v${version}"
  local msg="${RELEASE_MSG:-Release $component $tag}"

  info "Creating tag $tag in $repo..."
  if gh api "repos/$repo/git/refs" \
    --method POST \
    --field "ref=refs/tags/$tag" \
    --field "sha=$(gh api "repos/$repo/commits/HEAD" --jq '.sha' 2>/dev/null || echo 'HEAD')" \
    &>/dev/null; then
    success "Tag $tag created in $repo"
  else
    warn "Could not create tag in $repo (may already exist or insufficient permissions)"
  fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  header "🚀 OttoChain Release Coordinator"
  echo "  Component : ${BOLD}$COMPONENT${NC}"
  echo "  Version   : ${BOLD}$NEW_VERSION${NC}"
  echo "  Environment: $ENV_TARGET"
  $DRY_RUN && echo -e "  ${YELLOW}Mode      : DRY RUN — no changes will be made${NC}"
  echo ""

  # 1. Validate the component exists
  local current_version
  current_version=$(get_current_version "$COMPONENT")
  if [[ -z "$current_version" || "$current_version" == "null" ]]; then
    fatal "Unknown component: '$COMPONENT'. Valid components: $(get_all_components | tr '\n' ' ')"
  fi
  info "Current $COMPONENT version: $current_version"

  # 2. Validate new version is valid semver
  semver_valid "$NEW_VERSION" || fatal "Invalid semver: '$NEW_VERSION' (expected x.y.z)"

  # 3. Validate version is ascending (unless --force)
  if ! $FORCE; then
    if ! semver_gt "$NEW_VERSION" "$current_version"; then
      fatal "New version ($NEW_VERSION) must be greater than current ($current_version). Use --force to override."
    fi
  fi
  success "Semver validation passed ($current_version → $NEW_VERSION)"

  # 4. Cross-repo compatibility check
  if ! $NO_COMPAT; then
    validate_compatibility "$COMPONENT" "$NEW_VERSION" || \
      fatal "Compatibility check failed. Fix violations or use --no-compat to skip."
  fi

  # 5. Dry run stops here
  if $DRY_RUN; then
    echo ""
    warn "Dry run complete — no changes made."
    info "Would bump $COMPONENT: $current_version → $NEW_VERSION"
    return 0
  fi

  # 6. Create rollback snapshot
  header "📸 Creating rollback snapshot"
  local snapshot_file
  snapshot_file=$(create_snapshot "$COMPONENT" "$current_version" "$NEW_VERSION")
  success "Snapshot saved: $(basename "$snapshot_file")"

  # 7. Update versions.yaml
  header "📝 Updating versions.yaml"
  update_versions_file "$COMPONENT" "$NEW_VERSION"
  success "versions.yaml updated: $COMPONENT = $NEW_VERSION"

  # 8. Regenerate COMPATIBILITY.md
  header "📊 Regenerating COMPATIBILITY.md"
  if [[ -f "$SCRIPT_DIR/generate-compatibility.sh" ]]; then
    bash "$SCRIPT_DIR/generate-compatibility.sh" && success "COMPATIBILITY.md regenerated"
  else
    warn "generate-compatibility.sh not found — skipping COMPATIBILITY.md update"
  fi

  # 9. Commit changes in ottochain-deploy
  header "💾 Committing version change"
  cd "$ROOT_DIR"
  git add versions.yaml COMPATIBILITY.md 2>/dev/null || true
  local commit_msg="chore: bump $COMPONENT to v$NEW_VERSION"
  [[ -n "$RELEASE_MSG" ]] && commit_msg="$commit_msg — $RELEASE_MSG"
  git diff --cached --quiet || git commit -m "$commit_msg"
  success "Committed: $commit_msg"

  # 10. Create git tag in component repo (optional)
  if ! $NO_TAG; then
    header "🏷️  Creating release tag"
    create_git_tag "$COMPONENT" "$NEW_VERSION"
  fi

  echo ""
  header "✅ Release Complete"
  success "$COMPONENT bumped from $current_version to $NEW_VERSION"
  echo ""
  info "Next steps:"
  echo "  1. Push this repo: git push origin main (or open a PR)"
  echo "  2. CI will deploy to $ENV_TARGET environment automatically"
  echo "  3. Verify deployment: make status / scripts/check-versions.sh"
  echo "  4. To rollback: scripts/rollback-release.sh $COMPONENT $current_version"
  echo ""
  echo "  Snapshot for rollback: $(basename "$snapshot_file")"
}

main
