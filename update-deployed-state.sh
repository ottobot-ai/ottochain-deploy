#!/bin/bash

# Script to update deployed state after successful deployment
# This should be integrated into existing deployment workflows

set -e

ENVIRONMENT="${1:-scratch}"
DEPLOYED_STATE_FILE="deployed-state.json"

echo "📝 Updating deployed state for environment: $ENVIRONMENT"

# Create deployed state file if it doesn't exist
if [ ! -f "$DEPLOYED_STATE_FILE" ]; then
    echo "Creating initial deployed-state.json..."
    cat > $DEPLOYED_STATE_FILE << EOF
{
  "environments": {
    "development": {"current": {}, "previous": {}},
    "staging": {"current": {}, "previous": {}},
    "scratch": {"current": {}, "previous": {}},
    "production": {"current": {}, "previous": {}}
  },
  "last_updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
fi

# Read current versions from versions.yml
echo "Reading current versions from versions.yml..."

SERVICES_IMAGE=$(grep "services:" versions.yml | head -1 | cut -d' ' -f4)
EXPLORER_IMAGE=$(grep "explorer:" versions.yml | head -1 | cut -d' ' -f4)
METAGRAPH_IMAGE=$(grep "metagraph:" versions.yml | head -1 | cut -d' ' -f4)

TESSELLATION_VERSION=$(grep "tessellation:" versions.yml | sed 's/.*"\(.*\)".*/\1/')
OTTOCHAIN_VERSION=$(grep "ottochain:" versions.yml | sed 's/.*"\(.*\)".*/\1/')

# Get git commit SHAs (if available)
OTTOCHAIN_SHA=$(grep "ottochain:" versions.yml -A 10 | grep "ottochain:" | tail -1 | cut -d'"' -f2)
SERVICES_SHA=$(grep "services:" versions.yml -A 10 | grep "services:" | tail -1 | cut -d'"' -f2)
EXPLORER_SHA=$(grep "explorer:" versions.yml -A 10 | grep "explorer:" | tail -1 | cut -d'"' -f2)
DEPLOY_SHA=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

echo "Current deployment versions:"
echo "  Services: $SERVICES_IMAGE"
echo "  Explorer: $EXPLORER_IMAGE"
echo "  Tessellation: $TESSELLATION_VERSION"
echo "  OttoChain: $OTTOCHAIN_VERSION"

# Create new deployment state
NEW_DEPLOYMENT=$(cat << EOF
{
  "images": {
    "services": "$SERVICES_IMAGE",
    "explorer": "$EXPLORER_IMAGE",
    "metagraph": "$METAGRAPH_IMAGE"
  },
  "jars": {
    "tessellation": "$TESSELLATION_VERSION",
    "ottochain": "$OTTOCHAIN_VERSION"
  },
  "git": {
    "ottochain": "$OTTOCHAIN_SHA",
    "services": "$SERVICES_SHA",
    "explorer": "$EXPLORER_SHA",
    "deploy": "$DEPLOY_SHA"
  },
  "deployed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)

echo "New deployment state:"
echo "$NEW_DEPLOYMENT" | jq '.'

# Update deployed state: current -> previous, new -> current
echo "Updating deployed state..."

CURRENT_STATE=$(jq ".environments[\"$ENVIRONMENT\"].current" $DEPLOYED_STATE_FILE 2>/dev/null || echo '{}')

jq --argjson previous "$CURRENT_STATE" \
   --argjson current "$NEW_DEPLOYMENT" \
   --arg env "$ENVIRONMENT" \
   --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
   '.environments[$env].previous = $previous | 
    .environments[$env].current = $current |
    .last_updated = $timestamp' \
   $DEPLOYED_STATE_FILE > tmp.json && mv tmp.json $DEPLOYED_STATE_FILE

echo "✅ Deployed state updated successfully!"

echo "Updated state for $ENVIRONMENT:"
jq ".environments[\"$ENVIRONMENT\"]" $DEPLOYED_STATE_FILE

echo ""
echo "💡 Integration note:"
echo "This script should be called at the end of successful deployment workflows:"
echo "  ./update-deployed-state.sh $ENVIRONMENT"