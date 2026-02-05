# OttoChain 3×3 Deployment Guide

Complete guide for building and deploying OttoChain metagraph with 3 nodes per layer.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Global L0 (GL0)                          │
│   Node 1 (9000)  ←→  Node 2 (9010)  ←→  Node 3 (9020)      │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                   Metagraph L0 (ML0)                        │
│   Node 1 (9200)  ←→  Node 2 (9210)  ←→  Node 3 (9220)      │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                     Data L1 (DL1)                           │
│   Node 1 (9400)  ←→  Node 2 (9410)  ←→  Node 3 (9420)      │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Java 21 (Temurin recommended)
- sbt 1.x
- Docker with network `ottochain_ottochain`
- SSH access to deployment server

## Part 1: Building from Source

### 1.1 Build Tessellation

```bash
# Clone tessellation
git clone https://github.com/Constellation-Labs/tessellation.git /opt/tessellation
cd /opt/tessellation
git checkout develop  # or specific commit

# Build with custom version tag (MUST be semver-compatible)
# BAD:  ottochain-beta-2026.02.05 (fails sbt regex)
# GOOD: 0.1.0-ottochain-beta
export RELEASE_TAG="0.1.0-ottochain-beta"
sbt -DRELEASE_TAG=$RELEASE_TAG assembly

# Publish SDK locally for metakit
sbt -DRELEASE_TAG=$RELEASE_TAG sdk/publishLocal
```

### 1.2 Build Metakit

```bash
cd /opt/metakit

# Update Dependencies.scala to use matching tessellation version
# Change: val tessellation = "x.x.x" 
# To:     val tessellation = "0.1.0-ottochain-beta"

sbt -DRELEASE_TAG=$RELEASE_TAG clean compile publishLocal
```

### 1.3 Build OttoChain

```bash
cd /opt/ottochain-src

# Update Dependencies.scala to use matching metakit version
# Change: val metakit = "x.x.x"
# To:     val metakit = "0.1.0-ottochain-beta"

# Build all modules
sbt -DRELEASE_TAG=$RELEASE_TAG "project sharedData" assembly
sbt -DRELEASE_TAG=$RELEASE_TAG "project currencyL0" assembly
sbt -DRELEASE_TAG=$RELEASE_TAG "project currencyL1" assembly
sbt -DRELEASE_TAG=$RELEASE_TAG "project dataL1" assembly

# Copy JARs to deployment directory
mkdir -p /opt/ottochain/jars
cp modules/shared-data/target/scala-2.13/*-assembly*.jar /opt/ottochain/jars/
cp modules/l0/target/scala-2.13/*-assembly*.jar /opt/ottochain/jars/metagraph-l0.jar
cp modules/l1/target/scala-2.13/*-assembly*.jar /opt/ottochain/jars/currency-l1.jar
cp modules/data-l1/target/scala-2.13/*-assembly*.jar /opt/ottochain/jars/data-l1.jar
```

### 1.4 Get Tessellation JARs

```bash
# Copy from tessellation build
cp /opt/tessellation/modules/dag-l0/target/scala-2.13/*-assembly*.jar /opt/ottochain/jars/dag-l0.jar
cp /opt/tessellation/modules/keytool/target/scala-2.13/*-assembly*.jar /opt/ottochain/jars/cl-keytool.jar
cp /opt/tessellation/modules/wallet/target/scala-2.13/*-assembly*.jar /opt/ottochain/jars/cl-wallet.jar
```

## Part 2: Key Generation

Each node needs a unique key. Use tessellation's keytool (NOT Java keytool).

```bash
cd /opt/ottochain

# Generate keys for all nodes
for i in "" 3 4 5 6 7 8; do
  dir="keys${i}"
  mkdir -p $dir
  CL_KEYSTORE=$dir/key.p12 CL_KEYALIAS=alias CL_PASSWORD=password \
    java -jar jars/cl-keytool.jar generate
done

# Key assignments:
# keys/   - GL0 primary, ML0 primary, DL1 primary (same key OK for L0 layers)
# keys3/  - DL1-1
# keys4/  - DL1-2
# keys5/  - GL0-1
# keys6/  - GL0-2
# keys7/  - ML0-1
# keys8/  - ML0-2
```

### Get Wallet Address (Token ID)

```bash
CL_KEYSTORE=/opt/ottochain/keys/key.p12 CL_KEYALIAS=alias CL_PASSWORD=password \
  java -jar /opt/ottochain/jars/cl-wallet.jar show-address

# Save this - it becomes your TOKEN_ID
echo "DAG3yG9CRoYd4XF4PTBtLo95h8uiGNWYXXrASJGg" > /opt/ottochain/token-id
```

## Part 3: Genesis Setup

### 3.1 GL0 Genesis

Create genesis CSV with initial DAG allocation:

```bash
# Format: address,balance (no header)
echo "DAG3yG9CRoYd4XF4PTBtLo95h8uiGNWYXXrASJGg,1000000000000000" > /opt/ottochain/genesis.csv
```

### 3.2 ML0 Genesis Snapshot

**CRITICAL**: ML0 needs a BINARY genesis snapshot, not JSON!

```bash
cd /opt/ottochain
java -jar jars/metagraph-l0.jar create-genesis genesis.csv
# Creates: data/genesis.snapshot (binary format)
```

## Part 4: Docker Network

```bash
docker network create ottochain_ottochain 2>/dev/null || true
```

## Part 5: Environment Variables

Save these to `/opt/ottochain/env.sh`:

```bash
#!/bin/bash
export HOST_IP="5.78.90.207"
export GL0_PEER_ID=$(cat /opt/ottochain/gl0-peer-id 2>/dev/null || echo "")
export ML0_PEER_ID=$(cat /opt/ottochain/ml0-peer-id 2>/dev/null || echo "")
export TOKEN_ID=$(cat /opt/ottochain/token-id)

# Common settings
export CL_KEYALIAS=alias
export CL_PASSWORD=password
export CL_COLLATERAL=0
export CL_APP_ENV=dev
```

## Part 6: Starting the Cluster

### 6.1 Start GL0 Primary (Genesis Mode)

```bash
source /opt/ottochain/env.sh

docker run -d --name gl0 \
  --network ottochain_ottochain \
  -p 9000:9000 -p 9001:9001 -p 9002:9002 \
  -v /opt/ottochain/jars:/jars:ro \
  -v /opt/ottochain/keys:/keys:ro \
  -v /opt/ottochain/genesis.csv:/genesis.csv:ro \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9000 \
  -e CL_P2P_HTTP_PORT=9001 \
  -e CL_CLI_HTTP_PORT=9002 \
  -e CL_EXTERNAL_IP=$HOST_IP \
  -e CL_APP_ENV=$CL_APP_ENV \
  -e CL_COLLATERAL=$CL_COLLATERAL \
  eclipse-temurin:21-jdk \
  java -jar /jars/dag-l0.jar run-genesis /genesis.csv

# Wait for Ready state
sleep 30
curl -s http://localhost:9000/node/info | jq -r .state  # Should be "Ready"

# Save peer ID
curl -s http://localhost:9000/node/info | jq -r .id > /opt/ottochain/gl0-peer-id
```

### 6.2 Start ML0 Primary (Genesis Mode)

```bash
source /opt/ottochain/env.sh
GL0_PEER_ID=$(cat /opt/ottochain/gl0-peer-id)

docker run -d --name ml0 \
  --network ottochain_ottochain \
  -p 9200:9200 -p 9201:9201 -p 9202:9202 \
  -v /opt/ottochain/jars:/jars:ro \
  -v /opt/ottochain/keys:/keys:ro \
  -v /opt/ottochain/data:/data:ro \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9200 \
  -e CL_P2P_HTTP_PORT=9201 \
  -e CL_CLI_HTTP_PORT=9202 \
  -e CL_EXTERNAL_IP=$HOST_IP \
  -e CL_APP_ENV=$CL_APP_ENV \
  -e CL_GLOBAL_L0_PEER_HTTP_HOST=$HOST_IP \
  -e CL_GLOBAL_L0_PEER_HTTP_PORT=9000 \
  -e CL_GLOBAL_L0_PEER_ID=$GL0_PEER_ID \
  -e CL_COLLATERAL=$CL_COLLATERAL \
  eclipse-temurin:21-jdk \
  java -jar /jars/metagraph-l0.jar run-genesis /data/genesis.snapshot

sleep 30
curl -s http://localhost:9200/node/info | jq -r .id > /opt/ottochain/ml0-peer-id
```

### 6.3 Start DL1 Primary (Initial Validator)

```bash
source /opt/ottochain/env.sh
GL0_PEER_ID=$(cat /opt/ottochain/gl0-peer-id)
ML0_PEER_ID=$(cat /opt/ottochain/ml0-peer-id)

docker run -d --name dl1 \
  --network ottochain_ottochain \
  -p 9400:9400 -p 9401:9401 -p 9402:9402 \
  -v /opt/ottochain/jars:/jars:ro \
  -v /opt/ottochain/keys:/keys:ro \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9400 \
  -e CL_P2P_HTTP_PORT=9401 \
  -e CL_CLI_HTTP_PORT=9402 \
  -e CL_EXTERNAL_IP=$HOST_IP \
  -e CL_APP_ENV=$CL_APP_ENV \
  -e CL_GLOBAL_L0_PEER_HTTP_HOST=$HOST_IP \
  -e CL_GLOBAL_L0_PEER_HTTP_PORT=9000 \
  -e CL_GLOBAL_L0_PEER_ID=$GL0_PEER_ID \
  -e CL_L0_PEER_HTTP_HOST=$HOST_IP \
  -e CL_L0_PEER_HTTP_PORT=9200 \
  -e CL_L0_PEER_ID=$ML0_PEER_ID \
  -e CL_L0_TOKEN_IDENTIFIER=$TOKEN_ID \
  -e CL_COLLATERAL=$CL_COLLATERAL \
  eclipse-temurin:21-jdk \
  java -jar /jars/data-l1.jar run-initial-validator
```

### 6.4 Start Additional GL0 Validators

```bash
# GL0-1
docker run -d --name gl0-1 \
  --network ottochain_ottochain \
  -p 9010:9010 -p 9011:9011 -p 9012:9012 \
  -v /opt/ottochain/jars:/jars:ro \
  -v /opt/ottochain/keys5:/keys:ro \
  -e CL_KEYSTORE=/keys/key.p12 \
  -e CL_KEYALIAS=$CL_KEYALIAS \
  -e CL_PASSWORD=$CL_PASSWORD \
  -e CL_PUBLIC_HTTP_PORT=9010 \
  -e CL_P2P_HTTP_PORT=9011 \
  -e CL_CLI_HTTP_PORT=9012 \
  -e CL_EXTERNAL_IP=$HOST_IP \
  -e CL_APP_ENV=$CL_APP_ENV \
  -e CL_GLOBAL_L0_PEER_HTTP_HOST=$HOST_IP \
  -e CL_GLOBAL_L0_PEER_HTTP_PORT=9000 \
  -e CL_GLOBAL_L0_PEER_ID=$GL0_PEER_ID \
  -e CL_COLLATERAL=$CL_COLLATERAL \
  eclipse-temurin:21-jdk \
  java -jar /jars/dag-l0.jar run-validator

# GL0-2 (same pattern, ports 9020/9021/9022, keys6/)
```

### 6.5 Join Validators to Cluster

**CRITICAL**: CLI port is bound to localhost inside container. Must exec into container:

```bash
# Join GL0-1 to cluster
docker exec gl0-1 curl -s -X POST "http://127.0.0.1:9012/cluster/join" \
  -H "Content-Type: application/json" \
  -d "{\"id\": \"$GL0_PEER_ID\", \"ip\": \"$HOST_IP\", \"p2pPort\": 9001}"

# Join GL0-2
docker exec gl0-2 curl -s -X POST "http://127.0.0.1:9022/cluster/join" \
  -H "Content-Type: application/json" \
  -d "{\"id\": \"$GL0_PEER_ID\", \"ip\": \"$HOST_IP\", \"p2pPort\": 9001}"
```

Same pattern for ML0 and DL1 validators.

## Part 7: Verification

```bash
# Check all cluster sizes
echo "GL0: $(curl -s http://localhost:9000/cluster/info | jq '. | length')"
echo "ML0: $(curl -s http://localhost:9200/cluster/info | jq '. | length')"
echo "DL1: $(curl -s http://localhost:9400/cluster/info | jq '. | length')"

# Check node states
for p in 9000 9010 9020 9200 9210 9220 9400 9410 9420; do
  echo -n "Port $p: "
  curl -s http://localhost:$p/node/info | jq -r .state
done
```

## Critical Lessons Learned

### Port Mapping
- App binds to port specified by `CL_PUBLIC_HTTP_PORT` INSIDE container
- Docker mapping must match: `-p 9410:9410` (same inside and out)
- **CLI port is ALWAYS 9002 inside container** regardless of `CL_CLI_HTTP_PORT`
- The `CL_CLI_HTTP_PORT` env var only affects what's advertised, not actual binding
- Must use `docker exec` with port 9002 for join commands

### Environment Variables
- `CL_EXTERNAL_IP` - REQUIRED for validators to advertise correct IP
- `CL_APP_ENV=dev` - Must match across all nodes (causes EnvMismatch otherwise)
- `CL_L0_TOKEN_IDENTIFIER` - Must be IDENTICAL across all DL1 nodes (causes MetagraphIdMismatch)

### Genesis vs Validator
- **GL0**: First node uses `run-genesis /genesis.csv`, others use `run-validator`
- **ML0**: First node uses `run-genesis /path/to/genesis.snapshot`, others use `run-validator`
- **DL1**: First node uses `run-initial-validator`, others use `run-validator`

### ML0 Genesis Snapshot
- Must be BINARY format (use `metagraph-l0.jar create-genesis`)
- JSON format causes `NullPointerException in JsonBrotliBinarySerializer`

### Version Alignment
- Tessellation SDK version must EXACTLY match across all builds
- metakit depends on tessellation-sdk
- ottochain depends on metakit
- Mixing versions causes cryptic serialization errors

## Quick Reference: Port Convention

| Layer | Node | Public | P2P  | CLI  |
|-------|------|--------|------|------|
| GL0   | 1    | 9000   | 9001 | 9002 |
| GL0   | 2    | 9010   | 9011 | 9012 |
| GL0   | 3    | 9020   | 9021 | 9022 |
| ML0   | 1    | 9200   | 9201 | 9202 |
| ML0   | 2    | 9210   | 9211 | 9212 |
| ML0   | 3    | 9220   | 9221 | 9222 |
| DL1   | 1    | 9400   | 9401 | 9402 |
| DL1   | 2    | 9410   | 9411 | 9412 |
| DL1   | 3    | 9420   | 9421 | 9422 |

---
*Generated: 2026-02-05*
*Based on deployment to 5.78.90.207*
