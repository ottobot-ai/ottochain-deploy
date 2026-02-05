#!/bin/bash
# Build all required JARs for OttoChain deployment
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
JAR_DIR="$DEPLOY_DIR/docker/jars"

TESSELLATION_DIR="${TESSELLATION_DIR:-$HOME/.openclaw/workspace/tessellation}"
OTTOCHAIN_DIR="${OTTOCHAIN_DIR:-$HOME/.openclaw/workspace/ottochain}"

echo "=== OttoChain JAR Builder ==="
echo "Tessellation: $TESSELLATION_DIR"
echo "OttoChain: $OTTOCHAIN_DIR"
echo "Output: $JAR_DIR"
echo ""

# Source SDKMAN for sbt
source "$HOME/.sdkman/bin/sdkman-init.sh"

mkdir -p "$JAR_DIR"

# Build tessellation JARs (GL0, keytool, wallet)
echo "=== Building Tessellation ==="
cd "$TESSELLATION_DIR"

# Ensure we're on a good commit
git fetch origin
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "On branch: $CURRENT_BRANCH"

# Build required modules
echo "Building dag-l0 (GL0)..."
sbt "dagL0/assembly"
cp modules/dag-l0/target/scala-2.13/tessellation-dag-l0-assembly*.jar "$JAR_DIR/dag-l0.jar"

echo "Building keytool..."
sbt "keytool/assembly"
cp modules/keytool/target/scala-2.13/tessellation-keytool-assembly*.jar "$JAR_DIR/keytool.jar"

echo "Building wallet..."
sbt "wallet/assembly"
cp modules/wallet/target/scala-2.13/tessellation-wallet-assembly*.jar "$JAR_DIR/wallet.jar"

# Publish SDK locally for ottochain
echo "Publishing tessellation-sdk locally..."
sbt "sdk/publishLocal"

# Build OttoChain metagraph JARs
echo ""
echo "=== Building OttoChain Metagraph ==="
cd "$OTTOCHAIN_DIR"

echo "Building metagraph-l0 (ML0)..."
sbt "currencyL0/assembly"
cp modules/currency_l0/target/scala-2.13/*-assembly*.jar "$JAR_DIR/metagraph-l0.jar"

echo "Building data-l1 (DL1)..."
sbt "dataL1/assembly"
cp modules/data_l1/target/scala-2.13/*-assembly*.jar "$JAR_DIR/data-l1.jar"

# Currency L1 is required for metagraph token transactions
echo "Building currency-l1 (CL1)..."
sbt "currencyL1/assembly"
cp modules/currency_l1/target/scala-2.13/*-assembly*.jar "$JAR_DIR/currency-l1.jar"

echo ""
echo "=== Build Complete ==="
ls -lh "$JAR_DIR"
