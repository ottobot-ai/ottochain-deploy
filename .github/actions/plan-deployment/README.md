# Plan Deployment Composite Action

Analyzes and plans deployment changes for the target environment.
Compares current version configuration with targets and generates a structured deployment plan.

## Usage Example

```yaml
- name: Plan deployment
  uses: ./.github/actions/plan-deployment
  id: plan
  with:
    environment: scratch
    branch_name: ${{ github.ref_name }}
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `environment` | Yes | — | Target environment (development, staging, production, scratch) |
| `branch_name` | No | `${{ github.ref_name }}` | Git branch name |
| `versions_file` | No | `versions.yaml` | Path to versions YAML file |

## Outputs

| Output | Description |
|--------|-------------|
| `environment` | Resolved environment name |
| `plan_file` | Path to generated deployment plan file |
| `changes_detected` | Whether changes were detected (`true`/`false`) |

## Steps

1. **Install yq** — Installs `yq` YAML parser via `snap install yq`
2. **Generate deployment plan** — Runs `./scripts/compare-versions.sh` and writes to `deployment-plan.txt`
3. **Add plan to GitHub step summary** — Publishes `## 📋 Deployment Plan` to `$GITHUB_STEP_SUMMARY`

## Example with Conditional Deployment

```yaml
- name: Plan deployment
  uses: ./.github/actions/plan-deployment
  id: plan
  with:
    environment: staging

- name: Deploy only if changes detected
  if: steps.plan.outputs.changes_detected == 'true'
  uses: ./.github/actions/manage-containers
  with:
    action: restart
    hosts: 'node1,node2,node3'
```
