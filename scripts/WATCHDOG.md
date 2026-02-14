# Metagraph Layer Watchdog v2

Robust monitoring and auto-recovery for OttoChain metagraph layers.

## Overview

Two scripts work together for reliability:

| Script | Purpose |
|--------|---------|
| `layer-watchdog-v2.sh` | Continuous monitoring, detects stalls and stuck states |
| `coordinated-restart.sh` | Handles complex failures requiring multi-node coordination |

## Key Improvements Over v1

1. **State-aware restarts**: Detects `WaitingForDownload`, `Leaving`, `Offline` states
2. **Fresh-start deadlock detection**: Recognizes when GL0 genesis at ordinal 0 with stuck validators
3. **Restart loop prevention**: Limits restarts per hour, alerts instead of thrashing
4. **Coordinated restarts**: Proper sequencing for GL0 cluster recovery

## Installation

```bash
# On each metagraph node
scp scripts/layer-watchdog-v2.sh root@<NODE_IP>:/opt/ottochain/scripts/
scp scripts/coordinated-restart.sh root@<NODE_IP>:/opt/ottochain/scripts/
ssh root@<NODE_IP> "chmod +x /opt/ottochain/scripts/*.sh"

# Add cron (every 2 minutes)
ssh root@<NODE_IP> 'crontab -l 2>/dev/null | grep -v "layer-watchdog" ; echo "*/2 * * * * /opt/ottochain/scripts/layer-watchdog-v2.sh >> /var/log/layer-watchdog.log 2>&1"' | ssh root@<NODE_IP> crontab -
```

## Usage

### Watchdog

```bash
# Check all layers once
./layer-watchdog-v2.sh

# Show current status
./layer-watchdog-v2.sh --status

# Run as daemon (every 2min)
./layer-watchdog-v2.sh --daemon

# Check specific layer
./layer-watchdog-v2.sh gl0
```

### Coordinated Restart

```bash
# Check for deadlock
./coordinated-restart.sh --check

# Restart GL0 cluster only
./coordinated-restart.sh --layer gl0

# Full restart (all layers, preserve state)
./coordinated-restart.sh

# Full restart with state wipe (fresh genesis)
./coordinated-restart.sh --wipe

# Specify nodes explicitly
./coordinated-restart.sh --genesis-ip 5.78.90.207 --nodes "5.78.90.207 5.78.113.25 5.78.107.77"
```

## Configuration

Environment variables for `layer-watchdog-v2.sh`:

| Variable | Default | Description |
|----------|---------|-------------|
| `STALL_THRESHOLD_MINUTES` | 5 | Minutes without ordinal change = stall |
| `STUCK_STATE_THRESHOLD_MINUTES` | 3 | Minutes in bad state before restart |
| `COOLDOWN_MINUTES` | 10 | Minimum time between restarts |
| `MAX_RESTARTS_PER_HOUR` | 6 | Max restarts before alerting instead |
| `ALERT_WEBHOOK` | (none) | Webhook URL for alerts |

## Problem Detection

### Ordinal Stall
- Layer in `Ready` state but ordinal unchanged for 5+ minutes
- **Action**: Restart the layer

### Stuck State
- Layer in `WaitingForDownload`, `DownloadInProgress`, `Leaving`, or `Offline` for 3+ minutes
- **Action**: Restart (unless deadlock detected)

### Fresh-Start Deadlock
- GL0 genesis at ordinal 0
- 2+ validators stuck in `WaitingForDownload`/`DownloadInProgress`
- **Action**: Alert, recommend `coordinated-restart.sh --wipe`

### Restart Loop
- 6+ restarts within 1 hour
- **Action**: Stop restarting, send alert for manual intervention

## Logs

```bash
# Watchdog log
tail -f /var/log/layer-watchdog.log

# Restart history
cat /tmp/layer-watchdog-restarts.log
```

## Example Log Output

```
[2026-02-14 21:00:00] OK: gl0 ordinal 1234 -> 1235 (state=Ready)
[2026-02-14 21:00:00] OK: ml0 ordinal 5678 (unchanged 30s)
[2026-02-14 21:02:00] STUCK: cl1 in WaitingForDownload for 185s
[2026-02-14 21:02:00] RESTART: Restarting cl1 (reason: stuck in WaitingForDownload)...
[2026-02-14 21:02:05] RESTART: cl1 restarted successfully
[2026-02-14 21:04:00] DEADLOCK: Fresh-start deadlock detected (1 Ready, 2 stuck, ordinal=0)
[2026-02-14 21:04:00] ALERT: Fresh-start deadlock: GL0 genesis at ordinal 0, validators stuck. Need coordinated restart with wipe.
```

## Integration with Alerts

Set the `ALERT_WEBHOOK` environment variable to receive alerts:

```bash
export ALERT_WEBHOOK="https://hooks.slack.com/services/..."
# or for Discord:
export ALERT_WEBHOOK="https://discord.com/api/webhooks/..."
```

Alert format:
```json
{"text": "🚨 Layer Watchdog: <message>"}
```
