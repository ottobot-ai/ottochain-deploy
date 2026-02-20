# Manage Docker Containers Composite Action

Starts, stops, or restarts Docker containers on remote hosts via SSH.
Supports multiple hosts specified as a comma-separated list.

## Usage Example

```yaml
- name: Stop containers
  uses: ./.github/actions/manage-containers
  with:
    action: stop
    hosts: 'node1,node2,node3'
    ssh_key: ${{ secrets.HETZNER_SSH_KEY }}

- name: Start containers
  uses: ./.github/actions/manage-containers
  with:
    action: start
    hosts: 'node1,node2,node3'
    ssh_key: ${{ secrets.HETZNER_SSH_KEY }}
    profiles: 'genesis,validator'
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `action` | Yes | — | Action to perform: `start`, `stop`, or `restart` |
| `hosts` | Yes | — | Comma-separated list of hosts (e.g., `node1,node2,node3`) |
| `ssh_key` | No | `''` | SSH private key (if not already configured via setup-ssh) |
| `node_ips` | No | `''` | Comma-separated node IP addresses for dynamic host resolution |
| `profiles` | No | `''` | Docker compose profiles to use |
| `compose_file` | No | `docker-compose.yml` | Docker compose file path on remote host |

## Outputs

| Output | Description |
|--------|-------------|
| `container_status` | Final container status after action (from `docker ps`) |
| `affected_containers` | Comma-separated list of affected hosts |

## Steps

1. **Stop containers on hosts** *(if action == stop or restart)* — Iterates over hosts, runs `docker compose down` via SSH
2. **Start containers on hosts** *(if action == start or restart)* — Iterates over hosts, runs `docker compose up -d` via SSH
3. **Get container status** — Queries the first host for current container status

## Multi-Host SSH

The action uses `IFS=',' read -ra HOSTS <<< "${{ inputs.hosts }}"` to iterate hosts,
so you can manage multiple nodes in one step:

```yaml
hosts: 'node1,node2,node3'
```
