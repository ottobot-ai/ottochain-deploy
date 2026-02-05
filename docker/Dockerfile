# Multi-stage Dockerfile for OttoChain nodes
FROM eclipse-temurin:21-jre-jammy

# Install utilities
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy JARs (mounted or baked in)
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Default environment
ENV NODE_TYPE=gl0
ENV CL_KEYSTORE=/keys/key.p12
ENV CL_KEYALIAS=alias
ENV CL_PASSWORD=password

EXPOSE 9000 9001

ENTRYPOINT ["/app/entrypoint.sh"]
