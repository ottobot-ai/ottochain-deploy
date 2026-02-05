#!/bin/bash
# Setup GitHub Secrets for OttoChain CI/CD
# Run: ./scripts/setup-secrets.sh
#
# Prerequisites:
# - gh CLI installed and authenticated
# - Access to ottobot-ai/ottochain-deploy repo

set -e

REPO="ottobot-ai/ottochain-deploy"

echo "=== OttoChain CI/CD Secrets Setup ==="
echo ""
echo "This script will configure GitHub secrets for automated deployment."
echo "Repository: $REPO"
echo ""

# Check gh CLI
if ! command -v gh &> /dev/null; then
    echo "Error: gh CLI not installed. Install from https://cli.github.com/"
    exit 1
fi

# Check auth
if ! gh auth status &> /dev/null; then
    echo "Error: Not authenticated. Run 'gh auth login' first."
    exit 1
fi

echo "Enter values for each secret (or press Enter to skip):"
echo ""

# Function to set secret
set_secret() {
    local name=$1
    local description=$2
    local default=$3
    
    echo -n "$description [$name]: "
    read -r value
    
    if [ -n "$value" ]; then
        echo "$value" | gh secret set "$name" -R "$REPO"
        echo "  ✓ Set $name"
    elif [ -n "$default" ]; then
        echo "$default" | gh secret set "$name" -R "$REPO"
        echo "  ✓ Set $name (default)"
    else
        echo "  - Skipped $name"
    fi
}

# SSH Key (from file)
echo -n "Path to SSH private key [~/.ssh/hetzner_ottobot]: "
read -r ssh_key_path
ssh_key_path=${ssh_key_path:-~/.ssh/hetzner_ottobot}

if [ -f "$ssh_key_path" ]; then
    gh secret set HETZNER_SSH_KEY -R "$REPO" < "$ssh_key_path"
    echo "  ✓ Set HETZNER_SSH_KEY from $ssh_key_path"
else
    echo "  ⚠ SSH key file not found at $ssh_key_path"
fi

echo ""
set_secret "HETZNER_NODE1_IP" "Node 1 IP (genesis)" "5.78.90.207"
set_secret "HETZNER_NODE2_IP" "Node 2 IP" "5.78.113.25"
set_secret "HETZNER_NODE3_IP" "Node 3 IP" "5.78.107.77"
set_secret "HETZNER_SERVICES_IP" "Services IP" "5.78.121.248"
set_secret "CL_KEYSTORE_PASSWORD" "Keystore password" ""
set_secret "POSTGRES_PASSWORD" "Postgres password" ""

echo ""
echo "=== Secrets configured ==="
echo ""
echo "To verify: gh secret list -R $REPO"
echo ""
echo "To trigger deployment:"
echo "  git checkout -b release/scratch"
echo "  git push origin release/scratch --force"
