# Layer Watchdog

Monitors all metagraph layers (GL0, ML0, CL1, DL1) and auto-restarts stalled nodes.

## How It Works

1. Tracks ordinal progression for each layer
2. If ordinal unchanged for 4 minutes → restart container
3. 10-minute cooldown between restarts (prevents restart loops)

## Install (on each metagraph node)

```bash
# Copy script
scp scripts/layer-watchdog.sh root@<NODE_IP>:/opt/ottochain/scripts/
ssh root@<NODE_IP> "chmod +x /opt/ottochain/scripts/layer-watchdog.sh"

# Add cron (every 2 minutes)
ssh root@<NODE_IP> 'echo "*/2 * * * * /opt/ottochain/scripts/layer-watchdog.sh >> /var/log/layer-watchdog.log 2>&1" | crontab -'
```

## Usage

```bash
./layer-watchdog.sh              # Check all layers once
./layer-watchdog.sh ml0          # Check specific layer
./layer-watchdog.sh --daemon     # Continuous (every 2min)
```

## Configuration (env vars)

| Variable | Default | Description |
|----------|---------|-------------|
| `STALL_THRESHOLD_MINUTES` | 4 | Minutes without ordinal change = stall |
| `COOLDOWN_MINUTES` | 10 | Minutes between restarts |
| `DAEMON_INTERVAL` | 120 | Seconds between daemon checks |

## Logs

```bash
tail -f /var/log/layer-watchdog.log
```

Example output:
```
[2026-02-06 21:50:00] OK: gl0 ordinal=12345 -> 12346
[2026-02-06 21:50:00] OK: ml0 ordinal=5678 (unchanged 120s)
[2026-02-06 21:50:00] STALL: cl1 stuck at ordinal 999 for 250s
[2026-02-06 21:50:00] RESTART: cl1 restarted successfully
```
