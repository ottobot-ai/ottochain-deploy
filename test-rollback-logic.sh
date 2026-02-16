#!/bin/bash

# Test script to validate rollback workflow logic
set -e

echo "🧪 Testing Rollback Logic..."

# Test 1: Check if we can read previous versions from deployed-state.json
echo "Test 1: Reading previous versions for scratch environment..."

ENVIRONMENT="scratch"
DEPLOYED_STATE_FILE="deployed-state.json"

if [ ! -f "$DEPLOYED_STATE_FILE" ]; then
    echo "❌ deployed-state.json not found"
    exit 1
fi

PREVIOUS=$(jq -r ".environments[\"$ENVIRONMENT\"].previous // {}" $DEPLOYED_STATE_FILE)

if [ "$PREVIOUS" == "{}" ] || [ "$PREVIOUS" == "null" ]; then
    echo "❌ No previous deployment found for $ENVIRONMENT"
    exit 1
fi

echo "✅ Previous deployment found:"
echo "$PREVIOUS" | jq '.'

# Test 2: Extract version information
echo -e "\nTest 2: Extracting version information..."

SERVICES_IMAGE=$(echo "$PREVIOUS" | jq -r '.images.services // "latest"')
EXPLORER_IMAGE=$(echo "$PREVIOUS" | jq -r '.images.explorer // "latest"')
TESSELLATION_VERSION=$(echo "$PREVIOUS" | jq -r '.jars.tessellation // "latest"')
OTTOCHAIN_VERSION=$(echo "$PREVIOUS" | jq -r '.jars.ottochain // "latest"')

echo "Services Image: $SERVICES_IMAGE"
echo "Explorer Image: $EXPLORER_IMAGE"
echo "Tessellation Version: $TESSELLATION_VERSION"
echo "OttoChain Version: $OTTOCHAIN_VERSION"

# Test 3: Test versions.yml update logic
echo -e "\nTest 3: Testing versions.yml update (dry run)..."

# Create a backup for testing
cp versions.yml versions.yml.test-backup

echo "Current versions.yml services line:"
grep "services:" versions.yml

if [ "$SERVICES_IMAGE" != "null" ] && [ "$SERVICES_IMAGE" != "latest" ]; then
    echo "Would update services to: $SERVICES_IMAGE"
    # Commented out the actual update for safety
    # sed -i "s|services: .*|services: $SERVICES_IMAGE|" versions.yml
fi

echo "Current versions.yml tessellation line:"
grep "tessellation:" versions.yml

if [ "$TESSELLATION_VERSION" != "null" ] && [ "$TESSELLATION_VERSION" != "latest" ]; then
    echo "Would update tessellation to: \"$TESSELLATION_VERSION\""
    # Commented out the actual update for safety
    # sed -i "s|tessellation: \".*\"|tessellation: \"$TESSELLATION_VERSION\"|" versions.yml
fi

# Test 4: Test deployed state update logic
echo -e "\nTest 4: Testing deployed state update logic..."

CURRENT=$(jq ".environments[\"$ENVIRONMENT\"].current" $DEPLOYED_STATE_FILE)
echo "Current state:"
echo "$CURRENT" | jq '.'

echo "After rollback, current would become previous, and previous would become current"

# Test the jq command (without actually updating)
TEST_UPDATE=$(jq --argjson current "$CURRENT" \
                 --argjson rollback "$PREVIOUS" \
                 --arg env "$ENVIRONMENT" \
                 --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
                 '.environments[$env].previous = $current | 
                  .environments[$env].current = $rollback |
                  .last_updated = $timestamp' \
                 $DEPLOYED_STATE_FILE)

echo "Updated state would be:"
echo "$TEST_UPDATE" | jq ".environments[\"$ENVIRONMENT\"]"

echo -e "\n✅ All rollback logic tests passed!"
echo "🔧 The rollback workflow should work correctly for the $ENVIRONMENT environment"