#!/bin/bash
# Build the OttoChain metagraph Docker image
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$SCRIPT_DIR/../../docker"
JARS_DIR="${JARS_DIR:-$SCRIPT_DIR/../../jars}"

# Version tag
VERSION="${VERSION:-latest}"
IMAGE_NAME="${IMAGE_NAME:-ottochain}"

echo "Building $IMAGE_NAME:$VERSION"

# Ensure jars directory exists in docker context
mkdir -p "$DOCKER_DIR/jars"

# Copy JARs to docker context
echo "Copying JARs from $JARS_DIR..."
for jar in ml0.jar cl1.jar dl1.jar; do
    if [[ -f "$JARS_DIR/$jar" ]]; then
        cp "$JARS_DIR/$jar" "$DOCKER_DIR/jars/"
        echo "  ✓ $jar"
    else
        echo "  ✗ $jar not found!"
        exit 1
    fi
done

# Build image
cd "$DOCKER_DIR"
docker build \
    --build-arg TESSELLATION_VERSION="${TESSELLATION_VERSION:-v4.0.0-rc.2}" \
    -t "$IMAGE_NAME:$VERSION" \
    -f Dockerfile \
    .

echo ""
echo "✓ Built $IMAGE_NAME:$VERSION"

# Optionally push to registry
if [[ -n "$DOCKER_REGISTRY" ]]; then
    FULL_IMAGE="$DOCKER_REGISTRY/$IMAGE_NAME:$VERSION"
    docker tag "$IMAGE_NAME:$VERSION" "$FULL_IMAGE"
    docker push "$FULL_IMAGE"
    echo "✓ Pushed $FULL_IMAGE"
fi
