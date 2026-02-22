# Stability Spec: Alert Rules & GL0 Restart SOP

**Card:** 📜 Stability: Tessellation log analysis for error patterns (69962fd9fd)  
**Author:** @work (from @research findings, 2026-02-22)  
**Status:** Specification — ready for implementation by @work  
**Priority:** P1 (prevents future silent incidents)

---

## Background

@research completed full log analysis across all 3 cluster nodes on 2026-02-22 at ~02:48 CST.

**Key findings:**
- **Logs are clean** — no consensus failures, timeout storms, connection refused errors, snapshot lag, or OOM kills
- **One benign recurring pattern:** `EmberServerBuilderCompanionPlatform - Request handler failed` (5–10/day/node) — external probes sending malformed payloads; not actionable
- **GL0 split happened silently:** node1 GL0 restarted at 16:31:33 (timestamp from log) without seedlist → formed solo cluster. Boot log shows clean startup, zero error logs, zero peer join attempts
- **Node2/3 consensus clean:** `facilitatorCount=2`, all consensus rounds complete (`CollectingFacilities→Finished`)
- **Two critical alert patterns identified** for pipeline health monitoring (see Part 1)
- **Recovery log signatures documented** for identifying when rejoining is complete

---

## Part 1: Alert Rules Spec

### Critical Alert Rules

These two log patterns indicate **broken transaction pipeline** — silent failures that currently go undetected.

#### Alert 1: ML0 Zero-Updates (DL1 Pipeline Broken)

```
Pattern:  "Got 0 updates"   (in ML0 / ottochain-services logs)
Severity: 🔴 CRITICAL
Meaning:  ML0 received a snapshot with no transactions. If this persists >3 consecutive snapshots,
          DL1 is not producing blocks — either DL1 is down, or DL1 is on a different GL0 chain.
Threshold: 3+ consecutive occurrences (10+ minutes of 0 updates)
Action:    Page James + check DL1 status immediately
```

**Why not every occurrence?** ML0 legitimately receives 0-update snapshots during low-traffic periods. The alert should fire only on sustained absence (>3 in a row = DL1 pipeline broken).

**Log location:** ML0 application log, typically:
```
/var/log/ottochain-ml0/app.log
# or in Docker:
docker logs ottochain-ml0 | grep "Got 0 updates"
```

#### Alert 2: DL1 Download-Only (Not Producing Blocks)

```
Pattern:  "DownloadPerformed"  with no "BlockProduced" / "RoundFinished" in same time window
Severity: 🔴 CRITICAL  
Meaning:  DL1 is only downloading from peers, not participating in consensus rounds.
          This indicates DL1 is a follower (degraded mode) or is isolated.
Threshold: 5+ consecutive "DownloadPerformed" with 0 "RoundFinished" in 15-minute window
Action:    Page James + check DL1 peer count
```

**Log location:** DL1 application log:
```
/var/log/ottochain-dl1/app.log
# or Docker:
docker logs ottochain-dl1
```

#### Alert 3: GL0 Peer Count Drop (Split-Brain Detection)

```
Pattern:  GL0 API returns peerCount < 2 for the node1 GL0
Severity: 🔴 CRITICAL
Meaning:  GL0 on node1 has no peers — isolated (solo cluster / split-brain)
Threshold: peerCount == 0 persisted for > 2 minutes
Action:    Page James immediately — this is the current P0 scenario
Check:     curl http://5.78.90.207:9000/cluster/info | jq '.peers | length'
```

**Note:** A 2-node majority cluster (nodes 2+3) is valid with `peerCount=1` each. Only `peerCount=0` on any node indicates true isolation.

#### Alert 4: CL1 Container Down

```
Pattern:  `docker inspect ottochain-cl1` returns Status != "running" 
Severity: ⚠️ WARNING (currently all CL1 are down — P0 known issue)
Threshold: Container not running for > 5 minutes
Action:    Notify James — CL1 down = no consensus layer
```

### Non-Actionable Patterns (Ignore)

| Pattern | Location | Reason to Ignore |
|---------|----------|------------------|
| `EmberServerBuilderCompanionPlatform - Request handler failed` | All nodes, all layers | External probes sending malformed HTTP. Benign. 5–10/day/node. |
| `INFO ... SnapshotStorage - Snapshot stored at ordinal N` | GL0/ML0 | Normal operation, expected every ~5s |
| `INFO ... CollectingFacilities` | GL0/DL1 | Normal consensus start |
| `INFO ... Finished` (consensus round) | GL0/DL1 | Normal consensus end |

---

## Part 2: GL0 Restart SOP

**Scenario:** GL0 on node1 is isolated (no peers / wrong ordinal). Must rejoin nodes2+3's majority cluster.

### Pre-Checks (Before Restarting)

```bash
# 1. Confirm node2/3 GL0 are alive and forming majority
curl -s http://5.78.113.25:9000/cluster/info | jq '{state, peers: (.peers|length), ordinal}'
curl -s http://5.78.107.77:9000/cluster/info | jq '{state, peers: (.peers|length), ordinal}'
# Expected: state="Ready", peers=1 (each other), ordinal both ~same high number

# 2. Confirm node1 GL0 is isolated
curl -s http://5.78.90.207:9000/cluster/info | jq '{state, peers: (.peers|length), ordinal}'
# Expected: peers=0 (isolated), ordinal << node2/3 ordinal

# 3. Check node1 available RAM (must have 12+ GB free for catch-up)
ssh root@5.78.90.207 'free -h'
# Expected: ~12 GB available

# 4. Confirm seedlist env var is correctly configured (the root cause of split-brain)
ssh root@5.78.90.207 'docker inspect ottochain-gl0 | jq ".[0].Config.Env" | grep -i seed'
# Must see: CL_SEEDLIST_ADDRESSES=5.78.113.25,5.78.107.77 (or similar)
# If MISSING: that's why node1 formed solo cluster on restart
```

### Restart Procedure

```bash
# On node1 — restart GL0 with seedlist
ssh root@5.78.90.207

# Stop current isolated GL0
docker stop ottochain-gl0

# Verify seedlist is in docker-compose / env file
cat /opt/ottochain/docker-compose.yml | grep -A5 gl0
# Confirm CL_SEEDLIST_ADDRESSES is set to nodes 2+3

# Start GL0 (will attempt to join existing cluster)
docker start ottochain-gl0

# Monitor rejoin progress
docker logs -f ottochain-gl0 | grep -E "Joining|Peer|ordinal|DownloadPerformed|Ready"
```

### Expected Log Signatures During Rejoin

```
# Good signs (GL0 catching up):
"INFO ... Joining cluster"
"INFO ... DownloadPerformed ordinal=N"   ← downloading missing snapshots
"INFO ... Snapshot stored at ordinal N"  ← sync progressing

# Rejoined successfully:
"INFO ... CollectingFacilities"          ← participating in consensus
"INFO ... facilitatorCount=2"            ← node1 is now a peer with node2/3
"INFO ... Finished"                      ← consensus round complete
```

### Expected Timeline

| Phase | Duration | Indicator |
|-------|----------|-----------|
| Boot | 30–60s | Container starts, `INFO ... Starting` |
| Peer discovery | 30–120s | `INFO ... Joining cluster` |
| Snapshot download (catch-up 655 ordinals) | 3–10 min | `DownloadPerformed` repeated |
| Active consensus participant | After download | `facilitatorCount=3` |

**Total expected recovery time: 5–15 minutes** from `docker start` to full participation.

### Verify Rejoin Complete

```bash
# All three should show peerCount=2 and matching ordinals
for IP in 5.78.90.207 5.78.113.25 5.78.107.77; do
  echo "=== $IP ==="
  curl -s http://$IP:9000/cluster/info | jq '{state, peers: (.peers|length), ordinal}'
done
```

**Success criteria:**
- All 3 nodes: `state=Ready`, `peers=2`
- All 3 ordinals within ±2 of each other (slight lag expected)
- DL1 on all nodes also shows 3-node cluster (follows GL0)
- Bridge stops returning 500 on `POST /state-machine` requests

### CL1 Restart (After GL0 Rejoin)

CL1 is independently down on all 3 nodes. After GL0 stabilizes:

```bash
# On each node (in order: node1, node2, node3)
for IP in 5.78.90.207 5.78.113.25 5.78.107.77; do
  echo "Starting CL1 on $IP..."
  ssh root@$IP 'docker start ottochain-cl1'
  sleep 30  # Let it initialize before starting next node
done

# Verify CL1 cluster formed (all 3 should peer)
for IP in 5.78.90.207 5.78.113.25 5.78.107.77; do
  echo "=== CL1 on $IP ==="
  curl -s http://$IP:9010/cluster/info | jq '{state, peers: (.peers|length)}' 2>/dev/null || echo "CL1 not responding"
done
```

### Post-Recovery Checklist

- [ ] GL0: all 3 nodes `state=Ready, peers=2, ordinals matching`
- [ ] DL1: all 3 nodes in 3-node cluster, producing blocks (`RoundFinished` in logs)
- [ ] CL1: all 3 nodes `state=Ready, peers=2`
- [ ] ML0: `facilitatorCount=3`, receiving updates (`Got N updates` where N > 0)
- [ ] Bridge: `POST /state-machine` returns 200 (not 500)
- [ ] Indexer: transaction records appearing in DB

---

## Part 3: Root Cause Prevention

### Seedlist Configuration Fix

The split-brain was caused by node1 GL0 restarting **without seedlist addresses**. The fix:

1. **Verify seedlist is in all GL0 container configs** before any future restart:
   ```yaml
   # docker-compose.yml (GL0 service)
   environment:
     - CL_SEEDLIST_ADDRESSES=5.78.113.25,5.78.107.77  # node2, node3
     # OR
     - CL_L0_SEEDLIST=http://5.78.113.25:9000/cluster/info
   ```

2. **Add seedlist check to monitoring** — alert if GL0 container is missing seedlist env var:
   ```bash
   docker inspect ottochain-gl0 | jq '.[0].Config.Env[]' | grep -q "SEEDLIST" || echo "MISSING SEEDLIST"
   ```

3. **Add to restart runbook** — any GL0 restart must verify seedlist before `docker start`

### Alert Implementation Notes

Add to `packages/monitor/src/alerts/tessellation-alerts.ts`:

```typescript
// Check ML0 update count via log scan or metrics endpoint
async function checkML0UpdateRate(nodeIp: string): Promise<void> {
  // Option A: Parse recent logs
  const recentLogs = await getRecentLogs(nodeIp, 'ottochain-ml0', minutes=15);
  const zeroUpdates = recentLogs.filter(l => l.includes('Got 0 updates')).length;
  const totalSnapshots = recentLogs.filter(l => l.includes('Got')).length;
  
  if (totalSnapshots > 3 && zeroUpdates === totalSnapshots) {
    await fireAlert({
      severity: 'critical',
      message: `ML0 on ${nodeIp}: ${zeroUpdates} consecutive 0-update snapshots — DL1 pipeline broken`,
    });
  }
}

// Check GL0 peer count via API
async function checkGL0PeerCount(nodeIp: string): Promise<void> {
  const info = await fetch(`http://${nodeIp}:9000/cluster/info`).then(r => r.json());
  const peers = info.peers?.length ?? 0;
  
  if (peers === 0) {
    await fireAlert({
      severity: 'critical',
      message: `GL0 on ${nodeIp}: ISOLATED (0 peers) — potential split-brain`,
    });
  }
}
```

---

## Acceptance Criteria

### Alert Rules
- [ ] Alert fires within 5 min when ML0 has >3 consecutive 0-update snapshots
- [ ] Alert fires within 2 min when GL0 peerCount=0 on any node
- [ ] Alert fires within 5 min when DL1 has no `RoundFinished` in 15-minute window
- [ ] Alert fires within 5 min when CL1 container is stopped
- [ ] `EmberServerBuilderCompanionPlatform` errors do NOT trigger alerts
- [ ] Tests: `monitor/src/alerts/tessellation-alerts.test.ts` covers all 4 rule types

### GL0 Restart SOP
- [ ] SOP document reviewed by James
- [ ] Seedlist verified present in all 3 node GL0 configs
- [ ] Monitoring alert exists for missing seedlist env var
- [ ] GL0 restart tested on staging (when available) or documented with expected log signatures

### Recovery Validation
- [ ] Post-recovery script runs successfully against all 3 nodes
- [ ] Bridge health check passes after GL0 rejoins
