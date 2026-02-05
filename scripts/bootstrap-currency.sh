#!/bin/bash
# Bootstrap CL1 currency block production by sending an initial DAG transaction
# This is required because CL1 only produces blocks when there are transactions
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"

CL1_URL="${CL1_URL:-http://localhost:9300}"
GL0_URL="${GL0_URL:-http://localhost:9000}"

echo "=== Bootstrapping CL1 Currency Layer ==="
echo "CL1: $CL1_URL"
echo "GL0: $GL0_URL"

# Check CL1 is running
CL1_STATE=$(curl -s "$CL1_URL/node/info" | jq -r '.state // "DOWN"')
if [ "$CL1_STATE" != "Ready" ]; then
  echo "ERROR: CL1 not ready (state: $CL1_STATE)"
  exit 1
fi
echo "CL1 state: $CL1_STATE"

# Check cluster size
CL1_CLUSTER=$(curl -s "$CL1_URL/cluster/info" | jq 'length')
echo "CL1 cluster size: $CL1_CLUSTER"

if [ "$CL1_CLUSTER" -lt 3 ]; then
  echo "WARNING: CL1 cluster has fewer than 3 nodes, consensus may not work"
fi

# Use the SDK to send a bootstrap transaction
cd "$SCRIPT_DIR/../.." 

# Check if we have the bootstrap script
if [ ! -f "ottochain/sdk/bootstrap-currency.js" ]; then
  echo "Creating bootstrap script..."
  cat > /tmp/bootstrap-currency.js << 'EOF'
const { dag4 } = require('@stardust-collective/dag4');

const SEED_PHRASE = 'right off artist rare copy zebra shuffle excite evidence mercy isolate raise';
const DEST_ADDRESS = 'DAG87hragrbzrEQEz6VC5B7hvtm4wAemS7Zg8KFj';

async function main() {
  const cl1Url = process.argv[2] || 'http://localhost:9300';
  const gl0Url = process.argv[3] || 'http://localhost:9000';
  
  console.log('Connecting to CL1:', cl1Url);
  console.log('Connecting to GL0:', gl0Url);
  
  dag4.account.connect({
    networkVersion: '2.0',
    l0Url: gl0Url,
    l1Url: cl1Url,
  });
  
  await dag4.account.loginSeedPhrase(SEED_PHRASE);
  console.log('Wallet:', dag4.account.address);
  
  try {
    const balance = await dag4.network.getAddressBalance(dag4.account.address);
    console.log('Balance:', balance?.balance || 0);
  } catch (e) {
    console.log('Balance check failed:', e.message);
  }
  
  console.log('Sending 1 DATUM to', DEST_ADDRESS);
  try {
    const result = await dag4.account.transferDag(DEST_ADDRESS, 1, 0);
    console.log('Transaction result:', JSON.stringify(result, null, 2));
    console.log('\nBootstrap transaction sent! CL1 should start producing blocks.');
    console.log('Wait ~30s for currency snapshots to propagate to ML0.');
  } catch (e) {
    console.log('Transaction failed:', e.message);
    process.exit(1);
  }
}

main().catch(err => { console.error(err); process.exit(1); });
EOF
fi

# Run bootstrap using ottochain SDK (has dag4 installed)
if [ -d "/opt/ottochain-repo/sdk" ]; then
  SDK_DIR="/opt/ottochain-repo/sdk"
elif [ -d "$HOME/.openclaw/workspace/ottochain/sdk" ]; then
  SDK_DIR="$HOME/.openclaw/workspace/ottochain/sdk"
else
  echo "ERROR: Cannot find ottochain SDK directory"
  exit 1
fi

echo ""
echo "Running bootstrap transaction..."
cd "$SDK_DIR"
node /tmp/bootstrap-currency.js "$CL1_URL" "$GL0_URL"

echo ""
echo "=== Bootstrap Complete ==="
echo "CL1 should now start producing currency blocks."
echo "Run 'status.sh' to verify."
