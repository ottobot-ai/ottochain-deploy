# Secrets Configuration

This document describes the GitHub secrets required for OttoChain deployments.

## Infrastructure Secrets

Each environment requires an infrastructure secret containing server IPs and hostnames.
These are stored as JSON objects to keep sensitive infrastructure details out of the repo.

### Secret Names

| Environment | Secret Name | Description |
|-------------|-------------|-------------|
| Scratch | `SCRATCH_INFRASTRUCTURE` | Development/testing cluster |
| Staging | `STAGING_INFRASTRUCTURE` | Pre-production validation |
| Beta | `BETA_INFRASTRUCTURE` | External beta testing |
| Production | `PROD_INFRASTRUCTURE` | Production environment |

### Secret Format

Each infrastructure secret is a JSON object:

```json
{
  "nodes": [
    { "host": "1.2.3.4", "name": "node1" },
    { "host": "1.2.3.5", "name": "node2" },
    { "host": "1.2.3.6", "name": "node3" }
  ],
  "services_host": "1.2.3.7"
}
```

### Setting Up Secrets

1. Go to repository Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `SCRATCH_INFRASTRUCTURE` (or appropriate environment)
4. Value: JSON object as shown above
5. Click "Add secret"

### Using in Workflows

Workflows parse the infrastructure secret at runtime:

```yaml
- name: Load infrastructure config
  id: infra
  env:
    INFRA_JSON: ${{ secrets.SCRATCH_INFRASTRUCTURE }}
  run: |
    echo "node1_ip=$(echo $INFRA_JSON | jq -r '.nodes[0].host')" >> $GITHUB_OUTPUT
    echo "node2_ip=$(echo $INFRA_JSON | jq -r '.nodes[1].host')" >> $GITHUB_OUTPUT
    echo "node3_ip=$(echo $INFRA_JSON | jq -r '.nodes[2].host')" >> $GITHUB_OUTPUT
    echo "services_ip=$(echo $INFRA_JSON | jq -r '.services_host')" >> $GITHUB_OUTPUT
```

## SSH and Credentials

| Secret | Description |
|--------|-------------|
| `HETZNER_SSH_KEY` | SSH private key for Hetzner nodes |
| `CL_KEYSTORE_PASSWORD` | Constellation keystore password |
| `GITHUB_TOKEN` | (Auto-provided) For API access |

## Legacy Secrets (Deprecated)

These individual IP secrets are being phased out in favor of the JSON infrastructure secrets:

- `HETZNER_NODE1_IP` → Use `SCRATCH_INFRASTRUCTURE`
- `HETZNER_NODE2_IP` → Use `SCRATCH_INFRASTRUCTURE`
- `HETZNER_NODE3_IP` → Use `SCRATCH_INFRASTRUCTURE`
- `HETZNER_SERVICES_IP` → Use `SCRATCH_INFRASTRUCTURE`

Keep both during transition; remove legacy secrets once all workflows are updated.

## Security Notes

- **Never** commit IPs or credentials to the repository
- Infrastructure secrets are environment-specific
- Rotate SSH keys periodically
- Use GitHub Environments for production approval gates
