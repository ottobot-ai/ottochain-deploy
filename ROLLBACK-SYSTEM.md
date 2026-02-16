# Rollback System

This document describes the OttoChain deployment rollback system.

## Overview

The rollback system provides a safe way to revert deployments to their previous working state. It consists of:

1. **Rollback Workflow** (`.github/workflows/rollback.yml`) - GitHub Actions workflow that performs the rollback
2. **Deployed State Tracking** (`deployed-state.json`) - Tracks current and previous deployment versions for each environment
3. **Integration with Existing Deployment Workflows** - Leverages existing deployment automation

## How It Works

### Deployed State Tracking

The `deployed-state.json` file maintains the current and previous deployment state for each environment:

```json
{
  "environments": {
    "scratch": {
      "current": {
        "images": { "services": "...", "explorer": "..." },
        "jars": { "tessellation": "2.10.1", "ottochain": "0.5.0" },
        "git": { "ottochain": "...", "services": "..." },
        "deployed_at": "2026-02-16T14:35:00Z"
      },
      "previous": {
        "images": { "services": "...", "explorer": "..." },
        "jars": { "tessellation": "2.10.0", "ottochain": "0.4.0" },
        "git": { "ottochain": "...", "services": "..." },
        "deployed_at": "2026-02-15T14:35:00Z"
      }
    }
  }
}
```

### Rollback Process

1. **Validation Phase**:
   - Checks if user typed "CONFIRM" to proceed
   - Validates that previous deployment state exists
   - Shows rollback plan in GitHub Actions summary

2. **Rollback Execution**:
   - Updates `versions.yml` to previous versions
   - Triggers appropriate deployment workflow for the target environment
   - Updates deployed state (current → previous, rollback → current)
   - Commits changes to repository

## Usage

### Triggering a Rollback

1. Go to the GitHub Actions tab in the ottochain-deploy repository
2. Select "Rollback Deployment" workflow
3. Click "Run workflow"
4. Fill in the parameters:
   - **Environment**: Choose the target environment (development, staging, scratch, production)
   - **Confirm Rollback**: Type "CONFIRM" to proceed
5. Click "Run workflow"

### Example Rollback

To rollback the scratch environment:
1. Environment: `scratch`
2. Confirm Rollback: `CONFIRM`

The workflow will:
- Show you what versions will be rolled back to
- Update versions.yml with the previous versions
- Trigger the scratch deployment workflow
- Update the deployed state tracking

## Safety Features

- **Confirmation Required**: Must type "CONFIRM" to proceed
- **Environment Isolation**: Each environment tracked separately
- **Backup Creation**: Current versions.yml is backed up before rollback
- **State Validation**: Checks that previous deployment state exists
- **Audit Trail**: All changes committed to git with detailed commit messages

## Integration with Deployment Workflows

The rollback system integrates with existing deployment workflows:
- `release-scratch.yml` - For scratch environment
- `deploy-staging.yml` - For staging environment  
- `deploy-development.yml` - For development environment
- `deploy-production.yml` - For production environment

After updating `versions.yml`, the rollback workflow triggers the appropriate deployment workflow to actually perform the deployment.

## State Management

### Initial State

On the first deployment to an environment, there is no previous state to rollback to. The workflow will:
1. Create the deployed-state.json structure if it doesn't exist
2. Warn that no previous deployment exists
3. Fail gracefully with a clear error message

### State Updates

Each successful deployment should update the deployed state:
1. Move current state to previous
2. Set new deployment as current state
3. Update timestamp

**Note**: Current deployment workflows need to be updated to maintain the deployed-state.json file. This is a follow-up task.

## Files

- `.github/workflows/rollback.yml` - Main rollback workflow
- `deployed-state.json` - Deployment state tracking
- `versions.yml` - Current version specifications (updated during rollback)
- `ROLLBACK-SYSTEM.md` - This documentation

## Future Improvements

1. **Auto State Tracking**: Update existing deployment workflows to automatically maintain deployed-state.json
2. **Multi-Component Rollback**: Support selective rollback of individual components
3. **Rollback Testing**: Add smoke tests after rollback completion  
4. **Rollback History**: Track rollback history and prevent cascading rollbacks
5. **Integration Testing**: Add validation that rolled-back services are working correctly