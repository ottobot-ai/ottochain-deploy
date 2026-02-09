#!/bin/bash
# Generate COMPATIBILITY.md from versions.yml
# Usage: ./scripts/generate-compatibility.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSIONS_FILE="$ROOT_DIR/versions.yml"
OUTPUT_FILE="$ROOT_DIR/COMPATIBILITY.md"

# Check for yq
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required. Install with: brew install yq (or apt install yq)"
    exit 1
fi

# Extract versions
OTTOCHAIN_VERSION=$(yq '.components.ottochain.version' "$VERSIONS_FILE")
SDK_VERSION=$(yq '.components.sdk.version' "$VERSIONS_FILE")
SERVICES_VERSION=$(yq '.components.services.version' "$VERSIONS_FILE")
EXPLORER_VERSION=$(yq '.components.explorer.version' "$VERSIONS_FILE")
TESSELLATION_VERSION=$(yq '.components.tessellation.version' "$VERSIONS_FILE")

# Extract repos
OTTOCHAIN_REPO=$(yq '.components.ottochain.repo' "$VERSIONS_FILE")
SDK_REPO=$(yq '.components.sdk.repo' "$VERSIONS_FILE")
SDK_PACKAGE=$(yq '.components.sdk.package // "@ottochain/sdk"' "$VERSIONS_FILE")
SERVICES_REPO=$(yq '.components.services.repo' "$VERSIONS_FILE")
SERVICES_IMAGE=$(yq '.components.services.image' "$VERSIONS_FILE")
EXPLORER_REPO=$(yq '.components.explorer.repo' "$VERSIONS_FILE")
TESSELLATION_REPO=$(yq '.components.tessellation.repo' "$VERSIONS_FILE")

# Get current date
TODAY=$(date +%Y-%m-%d)

cat > "$OUTPUT_FILE" << EOF
# OttoChain Compatibility Matrix

> Auto-generated from \`versions.yml\` — do not edit manually.
> Run \`scripts/generate-compatibility.sh\` to update.
> Generated: $TODAY

## Current Release

| Component | Version | Repository |
|-----------|---------|------------|
| OttoChain Metagraph | \`$OTTOCHAIN_VERSION\` | [$OTTOCHAIN_REPO](https://github.com/$OTTOCHAIN_REPO) |
| OttoChain SDK | \`$SDK_VERSION\` | [$SDK_REPO](https://github.com/$SDK_REPO) • [npm](https://www.npmjs.com/package/$SDK_PACKAGE) |
| OttoChain Services | \`$SERVICES_VERSION\` | [$SERVICES_REPO](https://github.com/$SERVICES_REPO) |
| OttoChain Explorer | \`$EXPLORER_VERSION\` | [$EXPLORER_REPO](https://github.com/$EXPLORER_REPO) |
| Tessellation | \`$TESSELLATION_VERSION\` | [$TESSELLATION_REPO](https://github.com/$TESSELLATION_REPO) |

## Docker Images

| Service | Image | Tag |
|---------|-------|-----|
| Services | \`$SERVICES_IMAGE\` | \`v$SERVICES_VERSION\` |

## npm Packages

| Package | Version | Install |
|---------|---------|---------|
| $SDK_PACKAGE | \`$SDK_VERSION\` | \`npm install $SDK_PACKAGE@$SDK_VERSION\` |

## Dependency Graph

\`\`\`
┌─────────────────────────────────────────────────────────┐
│                    Tessellation SDK                      │
│                     (v$TESSELLATION_VERSION)                        │
└─────────────────────┬───────────────────────────────────┘
                      │
          ┌───────────┴───────────┐
          ▼                       ▼
┌─────────────────┐     ┌─────────────────┐
│    OttoChain    │     │  OttoChain SDK  │
│   Metagraph     │     │    (v$SDK_VERSION)     │
│    (v$OTTOCHAIN_VERSION)     │     │   $SDK_PACKAGE│
└────────┬────────┘     └────────┬────────┘
         │                       │
         │              ┌────────┴────────┐
         │              ▼                 ▼
         │    ┌─────────────────┐ ┌───────────────┐
         │    │    Services     │ │   Explorer    │
         │    │    (v$SERVICES_VERSION)     │ │   (v$EXPLORER_VERSION)    │
         │    └────────┬────────┘ └───────────────┘
         │             │
         └─────────────┴──────────┐
                                  ▼
                        ┌─────────────────┐
                        │  Metagraph API  │
                        │  (ML0/DL1/CL1)  │
                        └─────────────────┘
\`\`\`

## Verification

After deployment, verify versions match:

\`\`\`bash
# Check services versions
curl -s http://localhost:3030/version | jq .
curl -s http://localhost:3031/version | jq .

# Check SDK version in use
npm list $SDK_PACKAGE

# Check metagraph
curl -s http://localhost:9200/node/info | jq '.version'
\`\`\`

## Upgrade Checklist

- [ ] SDK version matches Services dependency
- [ ] Metagraph tessellation version matches cluster
- [ ] Docker images pulled with correct tags
- [ ] /version endpoints return expected values
- [ ] Integration tests pass

---

*See [versions.yml](./versions.yml) for the source of truth.*
EOF

echo "Generated $OUTPUT_FILE"
echo ""
echo "Versions:"
echo "  OttoChain:    $OTTOCHAIN_VERSION"
echo "  SDK:          $SDK_VERSION"
echo "  Services:     $SERVICES_VERSION"
echo "  Explorer:     $EXPLORER_VERSION"
echo "  Tessellation: $TESSELLATION_VERSION"
