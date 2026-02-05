# OttoChain Metagraph Base Image
# Supports: GL0, ML0, CL1, DL1 via JAR_FILE build arg

FROM eclipse-temurin:21-jre-alpine

ARG JAR_FILE=metagraph-l0.jar
ARG COMPONENT=metagraph-l0

LABEL org.opencontainers.image.source="https://github.com/ottobot-ai/ottochain"
LABEL org.opencontainers.image.description="OttoChain ${COMPONENT}"

# Install curl for health checks
RUN apk add --no-cache curl jq

# Create app directory
WORKDIR /app

# Copy JAR
COPY ${JAR_FILE} /app/app.jar

# Create data directory
RUN mkdir -p /data

# Environment defaults
ENV CL_PUBLIC_HTTP_PORT=9000 \
    CL_P2P_HTTP_PORT=9001 \
    CL_CLI_HTTP_PORT=9002 \
    CL_KEYSTORE=/keys/cl-keystore.p12 \
    CL_KEY_ALIAS=cl-keystore \
    JAVA_OPTS="-Xmx2g -Xms1g"

# Volumes
VOLUME ["/data", "/keys"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -sf http://localhost:${CL_PUBLIC_HTTP_PORT}/node/info | jq -e '.state == "Ready"' || exit 1

# Entrypoint script for flexible command handling
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["run-validator"]
