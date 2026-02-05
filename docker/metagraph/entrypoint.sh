#!/bin/sh
set -e

# OttoChain Metagraph Entrypoint
# Handles: run-genesis, run-validator, create-genesis

CMD=$1
shift

# Get host IP if not set
if [ -z "$CL_APP_HOST" ]; then
    CL_APP_HOST=$(hostname -i | awk '{print $1}')
fi

# Build Java args
JAVA_ARGS="$JAVA_OPTS -jar /app/app.jar"

case "$CMD" in
    create-genesis)
        # Create genesis snapshot from CSV
        echo "Creating genesis from $1..."
        exec java $JAVA_ARGS create-genesis "$@"
        ;;
    run-genesis)
        # Run as genesis node
        echo "Starting as genesis node..."
        exec java $JAVA_ARGS run-genesis "$@" --ip "$CL_APP_HOST"
        ;;
    run-validator)
        # Run as validator (join existing network)
        echo "Starting as validator..."
        exec java $JAVA_ARGS run-validator "$@" --ip "$CL_APP_HOST"
        ;;
    *)
        # Pass through any other command
        exec java $JAVA_ARGS "$CMD" "$@"
        ;;
esac
