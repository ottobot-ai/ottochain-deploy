#!/bin/bash
set -e

JARS_DIR="${JARS_DIR:-/jars}"
DATA_DIR="${DATA_DIR:-/data}"

mkdir -p $DATA_DIR

# Select JAR based on NODE_TYPE
case $NODE_TYPE in
  gl0)
    JAR="$JARS_DIR/dag-l0.jar"
    ;;
  ml0)
    JAR="$JARS_DIR/metagraph-l0.jar"
    ;;
  cl1)
    JAR="$JARS_DIR/currency-l1.jar"
    ;;
  dl1)
    JAR="$JARS_DIR/data-l1.jar"
    ;;
  *)
    echo "Unknown NODE_TYPE: $NODE_TYPE"
    exit 1
    ;;
esac

if [ ! -f "$JAR" ]; then
  echo "JAR not found: $JAR"
  ls -la $JARS_DIR/
  exit 1
fi

echo "Starting $NODE_TYPE with $JAR"

# Build command args
ARGS="run-validator"

# Genesis mode for initial startup
if [ "$GENESIS_MODE" = "true" ]; then
  ARGS="run-genesis genesis.snapshot"
fi

# Rollback mode
if [ "$ROLLBACK_MODE" = "true" ]; then
  ARGS="run-rollback"
fi

# Execute
exec java $JAVA_OPTS \
  -jar $JAR \
  $ARGS
