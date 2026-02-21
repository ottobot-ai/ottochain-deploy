# Setup SSH Composite Action

Configures SSH access to all Hetzner cluster nodes and services host.
Writes the private key and sets up `~/.ssh/config` entries for use with `ssh` commands.

## Usage Example

```yaml
- name: Setup SSH
  uses: ./.github/actions/setup-ssh
  with:
    hetzner_ssh_key: ${{ secrets.HETZNER_SSH_KEY }}
    node1_ip: ${{ secrets.HETZNER_NODE1_IP }}
    node2_ip: ${{ secrets.HETZNER_NODE2_IP }}
    node3_ip: ${{ secrets.HETZNER_NODE3_IP }}
    services_ip: ${{ secrets.HETZNER_SERVICES_IP }}
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `hetzner_ssh_key` | Yes | — | SSH private key for Hetzner nodes |
| `node1_ip` | No | `''` | IP address of node1 |
| `node2_ip` | No | `''` | IP address of node2 |
| `node3_ip` | No | `''` | IP address of node3 |
| `services_ip` | No | `''` | IP address of services node |

## Outputs

This action has no outputs. It configures `~/.ssh/config` as a side effect.

| Side Effect | Description |
|-------------|-------------|
| `~/.ssh/hetzner` | SSH private key file (chmod 600) |
| `~/.ssh/config` | SSH config with entries for node1, node2, node3, services |

## Steps

1. **Create SSH directory and write key** — Creates `~/.ssh/`, writes the key file, sets `chmod 600`
2. **Configure SSH hosts** — Writes `~/.ssh/config` with entries for `node1`, `node2`, `node3`, `services`
3. **Set SSH permissions** — Sets `chmod 700 ~/.ssh` and `chmod 600 ~/.ssh/config`

## After Setup

SSH aliases available: `node1`, `node2`, `node3`, `services`

```bash
ssh node1 "docker ps"
ssh services "docker compose ps"
```
