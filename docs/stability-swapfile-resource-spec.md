# Stability Spec: Swapfile Setup & Resource Alert Thresholds

**Card:** 📊 Stability: Node resource profiling (69962fd9dae)  
**Author:** @work (from @research findings, 2026-02-22)  
**Status:** Specification — ready for implementation by @work  
**Priority:** P1 (prevents future OOM scenarios)

---

## Background

@research completed a full resource profile across all 4 cluster nodes on 2026-02-22 at ~02:48 CST.

**Key findings:**
- **No current resource starvation** — GL0 split-brain was a seedlist/boot failure, not resource-caused
- All nodes have **9–12 GB free RAM** and **<13% disk** usage
- **Swap is completely absent on all nodes** — a latent OOM risk if layers grow during catch-up
- Active GL0 nodes (node2, node3) consume ~2.97 GB each during consensus; node1's isolated GL0 uses only 612 MB (idle, no peers)
- GL0 restart on node1 is **safe**: has 12 GB headroom, GL0 will grow 612 MB → ~3 GB during catch-up sync
- 4 layers/node is **feasible** (estimated total ~4.7 GB/node at peak)

---

## Part 1: Swapfile Setup Spec

### Why Swapfile?

Tessellation JVM layers use off-heap memory (buffers, proto serialization, bloom filters) that can spike during snapshot replay or large consensus rounds. Without swap, the OOM killer terminates the layer process with no warning and no recovery. Swap provides a safety buffer that converts a hard crash into a performance degradation — allowing the process to continue and alert to fire.

8 GB swapfile gives ~2× safety factor over expected peak usage (4.7 GB active + 3 GB growth buffer).

### Target Nodes

All 4 Hetzner nodes:
- `node1`: 10.0.0.1
- `node2`: 10.0.0.2
- `node3`: 10.0.0.3
- `services`: 10.0.0.4

### Swapfile Setup Procedure

```bash
#!/bin/bash
# Run on each node as root

# 1. Create 8 GB swapfile
fallocate -l 8G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# 2. Persist across reboots
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# 3. Tune swappiness (prefer RAM, use swap only under pressure)
sysctl vm.swappiness=10
echo 'vm.swappiness=10' >> /etc/sysctl.conf

# 4. Verify
swapon --show
free -h
```

### Expected State After Setup

```
NAME      TYPE  SIZE  USED PRIO
/swapfile file    8G    0B   -2
```

### Ansible Playbook (for ottochain-deploy)

Add to `ansible/roles/hetzner_node/tasks/swapfile.yml`:

```yaml
---
- name: Check if swapfile exists
  stat:
    path: /swapfile
  register: swapfile_stat

- name: Create 8GB swapfile
  command: fallocate -l 8G /swapfile
  when: not swapfile_stat.stat.exists

- name: Set swapfile permissions
  file:
    path: /swapfile
    mode: '0600'
  when: not swapfile_stat.stat.exists

- name: Initialize swapfile
  command: mkswap /swapfile
  when: not swapfile_stat.stat.exists

- name: Enable swapfile
  command: swapon /swapfile
  when: not swapfile_stat.stat.exists

- name: Persist swap in fstab
  lineinfile:
    path: /etc/fstab
    line: '/swapfile none swap sw 0 0'
    state: present

- name: Set swappiness
  sysctl:
    name: vm.swappiness
    value: '10'
    sysctl_set: true
    state: present
    reload: true
```

---

## Part 2: Resource Alert Thresholds

### Monitoring Architecture

The cluster monitor runs on `services` node (10.0.0.4). Add resource checks to the existing monitor cron/loop.

### Alert Thresholds

#### Memory Alerts

| Threshold | Value | Severity | Action |
|-----------|-------|----------|--------|
| RAM usage > 70% | ~14 GB on 20 GB node | ⚠️ WARNING | Log + Telegram notify |
| RAM usage > 85% | ~17 GB on 20 GB node | 🔴 CRITICAL | Page James immediately |
| Swap usage > 50% | > 4 GB swap used | ⚠️ WARNING | Investigate layer growth |
| Swap usage > 80% | > 6.4 GB swap used | 🔴 CRITICAL | Page James — restart candidate |

**Rationale:** Active GL0 = ~3 GB, ML0 = ~2 GB, DL1 = ~1.5 GB, CL1 = ~1 GB → total ~7.5 GB per node with all layers. 70% threshold = ~14 GB gives 6.5 GB headroom before approaching OOM zone.

#### Disk Alerts

| Threshold | Value | Severity |
|-----------|-------|----------|
| Disk usage > 70% | — | ⚠️ WARNING |
| Disk usage > 85% | — | 🔴 CRITICAL |

Tessellation snapshot data grows linearly with ordinal. At current disk usage <13%, this is low priority but should be monitored.

#### CPU Alerts

| Threshold | Value | Severity |
|-----------|-------|----------|
| CPU > 90% sustained (5 min avg) | — | ⚠️ WARNING |
| Load avg > (2 × CPU count) | — | ⚠️ WARNING |

Tessellation is memory-intensive, not CPU-bound. CPU spikes are expected during consensus rounds but should normalize. Sustained high CPU may indicate consensus storm.

#### Per-Layer Process Alerts

Monitor each Tessellation layer process (GL0, ML0, DL1, CL1) individually:

```bash
# Expected RSS ranges (healthy, steady-state)
GL0:  2.5–3.5 GB  (active node)  /  300–800 MB (isolated/degraded)
ML0:  1.5–2.5 GB
DL1:  1.0–1.8 GB
CL1:  800 MB–1.5 GB
```

Alert if **any layer process is absent** (container stopped):
- CL1 down = alert (currently ALL CL1 containers are dead — known P0 issue)
- GL0 RSS < 500 MB on an otherwise-active node = likely isolated/split-brain

### Alert Implementation

Add to `packages/monitor/src/alerts/resource-alerts.ts`:

```typescript
interface ResourceAlert {
  nodeIp: string;
  layer: 'GL0' | 'ML0' | 'DL1' | 'CL1' | 'HOST';
  metric: 'ram_pct' | 'swap_pct' | 'disk_pct' | 'cpu_pct' | 'process_absent';
  value: number;
  threshold: number;
  severity: 'warning' | 'critical';
  message: string;
}

const THRESHOLDS = {
  ram_warning_pct:   70,
  ram_critical_pct:  85,
  swap_warning_pct:  50,
  swap_critical_pct: 80,
  disk_warning_pct:  70,
  disk_critical_pct: 85,
  cpu_warning_pct:   90,
};
```

The monitor should SSH to each node and run:
```bash
# Memory snapshot
free -b | awk '/^Mem:/{printf "ram_total=%d ram_used=%d\n",$2,$3}'
free -b | awk '/^Swap:/{printf "swap_total=%d swap_used=%d\n",$2,$3}'

# Disk
df -B1 / | awk 'NR==2{printf "disk_total=%d disk_used=%d\n",$2,$3}'

# Per-layer process RSS (using docker stats)
docker stats --no-stream --format "{{.Name}} {{.MemUsage}}" 2>/dev/null
```

---

## Implementation Notes

1. **Swapfile first** — add to Ansible role, run on all 4 nodes before GL0 restart
2. **Alert thresholds** — low-risk to add monitoring; don't need cluster downtime
3. **Per-layer monitoring** — the "GL0 RSS < 500 MB on active node" heuristic is a proxy for split-brain detection (see alert-rules spec for the definitive approach)

## Acceptance Criteria

- [ ] All 4 nodes show `swapon --show` with 8 GB swap
- [ ] `vm.swappiness=10` persisted in `/etc/sysctl.conf`
- [ ] Monitor alerts fire when RAM > 70% on any node
- [ ] Monitor alerts fire when swap > 50% on any node
- [ ] Disk alerts fire when disk > 70% on any node
- [ ] Tests: `monitor/src/alerts/resource-alerts.test.ts` covers threshold logic
