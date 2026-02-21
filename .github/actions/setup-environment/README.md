# Setup Environment Composite Action

Configures environment variables and creates `.env` files for deployment environments.
Supports optional token and peer ID configuration.

## Usage Example

```yaml
- name: Setup environment
  uses: ./.github/actions/setup-environment
  with:
    environment: staging
    keystore_password: ${{ secrets.CL_KEYSTORE_PASSWORD }}
    token_id: ${{ needs.deploy.outputs.token_id }}
    gl0_peer_id: ${{ needs.deploy.outputs.gl0_peer_id }}
    ml0_peer_id: ${{ needs.deploy.outputs.ml0_peer_id }}
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `environment` | Yes | — | Environment name (development, staging, production, scratch) |
| `keystore_password` | Yes | — | CL keystore password (`CL_PASSWORD` in .env) |
| `token_id` | No | `''` | Token ID for the metagraph (optional) |
| `gl0_peer_id` | No | `''` | GL0 layer peer ID (optional) |
| `ml0_peer_id` | No | `''` | ML0 layer peer ID (optional) |
| `env_file` | No | `.env` | Path to write the .env file |

## Outputs

| Output | Description |
|--------|-------------|
| `config_created` | Whether environment config was created (`true`) |
| `env_file_path` | Path to the created .env file |

## Steps

1. **Create environment .env file** — Writes `.env` with `CL_PASSWORD`, `DEPLOY_ENVIRONMENT`, peer IDs
2. **Add optional token ID configuration** *(if `token_id` is set)* — Appends `METAGRAPH_TOKEN_ID` to `.env`

## Generated .env Format

```dotenv
CL_PASSWORD=<keystore_password>
DEPLOY_ENVIRONMENT=staging
GL0_PEER_ID=<gl0_peer_id>
ML0_PEER_ID=<ml0_peer_id>
METAGRAPH_TOKEN_ID=<token_id>  # if provided
```
