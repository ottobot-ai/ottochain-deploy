# OttoChain Metagraph Docker Image
# Based on tessellation, adds metagraph JARs

ARG TESSELLATION_VERSION=v4.0.0-rc.2
FROM constellationnetwork/tessellation:${TESSELLATION_VERSION}

# Copy metagraph JARs (ml0, cl1, dl1)
COPY jars/ml0.jar /tessellation/jars/ml0.jar
COPY jars/cl1.jar /tessellation/jars/cl1.jar
COPY jars/dl1.jar /tessellation/jars/dl1.jar

# The entrypoint from tessellation handles everything
