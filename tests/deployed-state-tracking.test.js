/**
 * TDD Tests for Deployed State Auto-Update Feature
 * Card: 69962fdb74f589762cc99aad
 * 
 * These tests MUST FAIL initially to prove TDD approach.
 * They verify the 8 acceptance criteria from the specification.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync, existsSync } from 'fs';
import { load } from 'js-yaml';
import { join } from 'path';

const REPO_ROOT = process.cwd();
const WORKFLOWS_DIR = join(REPO_ROOT, '.github/workflows');

describe('Deployed State Auto-Update - TDD Tests', () => {
  describe('AC1-3: deploy-metagraph.yml workflow structure', () => {
    it('should have update-deployed-state job in deploy-metagraph.yml', () => {
      const workflowPath = join(WORKFLOWS_DIR, 'deploy-metagraph.yml');
      expect(existsSync(workflowPath)).toBe(true);
      
      const workflowContent = readFileSync(workflowPath, 'utf8');
      const workflow = load(workflowContent);
      
      // Should have update-deployed-state job
      expect(workflow.jobs).toHaveProperty('update-deployed-state');
      
      const updateJob = workflow.jobs['update-deployed-state'];
      
      // Job should depend on deploy job
      expect(updateJob.needs).toEqual('deploy');
      
      // Job should only run on success
      expect(updateJob.if).toBe('success()');
      
      // Job should have correct permissions
      expect(updateJob.permissions).toEqual({ contents: 'write' });
    });

    it('should update ottochain version in deployed.scratch section', () => {
      const workflowPath = join(WORKFLOWS_DIR, 'deploy-metagraph.yml');
      const workflowContent = readFileSync(workflowPath, 'utf8');
      const workflow = load(workflowContent);
      
      const updateJob = workflow.jobs['update-deployed-state'];
      const steps = updateJob.steps;
      
      // Should have step that updates deployed.scratch.ottochain
      const updateStep = steps.find(step => 
        step.name && step.name.includes('Update deployed state')
      );
      expect(updateStep).toBeTruthy();
      
      // Should use yq to update versions.yaml
      expect(updateStep.run).toContain('yq');
      expect(updateStep.run).toContain('deployed.scratch.ottochain');
      expect(updateStep.run).toContain('components.ottochain.version');
    });

    it('should update timestamp in deployed.scratch section', () => {
      const workflowPath = join(WORKFLOWS_DIR, 'deploy-metagraph.yml');
      const workflowContent = readFileSync(workflowPath, 'utf8');
      const workflow = load(workflowContent);
      
      const updateJob = workflow.jobs['update-deployed-state'];
      const steps = updateJob.steps;
      
      const updateStep = steps.find(step => 
        step.name && step.name.includes('Update deployed state')
      );
      
      // Should update timestamp with UTC ISO string
      expect(updateStep.run).toContain('deployed.scratch.timestamp');
      expect(updateStep.run).toContain('date -u +%Y-%m-%dT%H:%M:%SZ');
    });

    it('should update workflow_run with GitHub run ID', () => {
      const workflowPath = join(WORKFLOWS_DIR, 'deploy-metagraph.yml');
      const workflowContent = readFileSync(workflowPath, 'utf8');
      const workflow = load(workflowContent);
      
      const updateJob = workflow.jobs['update-deployed-state'];
      const steps = updateJob.steps;
      
      const updateStep = steps.find(step => 
        step.name && step.name.includes('Update deployed state')
      );
      
      // Should update workflow_run with GITHUB_RUN_ID
      expect(updateStep.run).toContain('deployed.scratch.workflow_run');
      expect(updateStep.run).toContain('$GITHUB_RUN_ID');
    });
  });

  describe('AC4: deploy-services.yml workflow structure', () => {
    it('should have update-deployed-state job in deploy-services.yml', () => {
      const workflowPath = join(WORKFLOWS_DIR, 'deploy-services.yml');
      expect(existsSync(workflowPath)).toBe(true);
      
      const workflowContent = readFileSync(workflowPath, 'utf8');
      const workflow = load(workflowContent);
      
      // Should have update-deployed-state job
      expect(workflow.jobs).toHaveProperty('update-deployed-state');
      
      const updateJob = workflow.jobs['update-deployed-state'];
      
      // Job should depend on deploy job
      expect(updateJob.needs).toEqual('deploy');
      
      // Job should only run on success
      expect(updateJob.if).toBe('success()');
      
      // Job should have correct permissions
      expect(updateJob.permissions).toEqual({ contents: 'write' });
    });

    it('should update services, explorer, and monitoring versions', () => {
      const workflowPath = join(WORKFLOWS_DIR, 'deploy-services.yml');
      const workflowContent = readFileSync(workflowPath, 'utf8');
      const workflow = load(workflowContent);
      
      const updateJob = workflow.jobs['update-deployed-state'];
      const steps = updateJob.steps;
      
      const updateStep = steps.find(step => 
        step.name && step.name.includes('Update deployed state')
      );
      expect(updateStep).toBeTruthy();
      
      // Should update all three service components
      expect(updateStep.run).toContain('deployed.scratch.services');
      expect(updateStep.run).toContain('deployed.scratch.explorer');  
      expect(updateStep.run).toContain('deployed.scratch.monitoring');
      
      // Should read from components section
      expect(updateStep.run).toContain('components.services.version');
      expect(updateStep.run).toContain('components.explorer.version');
      expect(updateStep.run).toContain('components.monitoring.version');
    });
  });

  describe('AC5: Failure handling - if: success() gate', () => {
    it('should only run update-deployed-state job on successful deploy', () => {
      const workflows = ['deploy-metagraph.yml', 'deploy-services.yml'];
      
      workflows.forEach(workflowFile => {
        const workflowPath = join(WORKFLOWS_DIR, workflowFile);
        const workflowContent = readFileSync(workflowPath, 'utf8');
        const workflow = load(workflowContent);
        
        const updateJob = workflow.jobs['update-deployed-state'];
        
        // Must have if: success() to prevent running on failure
        expect(updateJob.if).toBe('success()');
      });
    });
  });

  describe('AC6: No-op commit detection', () => {
    it('should skip commit when no changes are detected', () => {
      const workflows = ['deploy-metagraph.yml', 'deploy-services.yml'];
      
      workflows.forEach(workflowFile => {
        const workflowPath = join(WORKFLOWS_DIR, workflowFile);
        const workflowContent = readFileSync(workflowPath, 'utf8');
        const workflow = load(workflowContent);
        
        const updateJob = workflow.jobs['update-deployed-state'];
        const steps = updateJob.steps;
        
        const commitStep = steps.find(step => 
          step.name && step.name.includes('Commit')
        );
        expect(commitStep).toBeTruthy();
        
        // Should check for changes before committing
        expect(commitStep.run).toContain('git diff --cached --quiet');
        expect(commitStep.run).toContain('No changes, skipping commit');
      });
    });
  });

  describe('AC7: [skip ci] mechanism to prevent deployment loops', () => {
    it('should include [skip ci] in commit message', () => {
      const workflows = ['deploy-metagraph.yml', 'deploy-services.yml'];
      
      workflows.forEach(workflowFile => {
        const workflowPath = join(WORKFLOWS_DIR, workflowFile);
        const workflowContent = readFileSync(workflowPath, 'utf8');
        const workflow = load(workflowContent);
        
        const updateJob = workflow.jobs['update-deployed-state'];
        const steps = updateJob.steps;
        
        const commitStep = steps.find(step => 
          step.name && step.name.includes('Commit')
        );
        
        // Should use [skip ci] in commit message
        expect(commitStep.run).toContain('[skip ci]');
      });
    });
  });

  describe('AC8: RELEASE-RUNBOOK.md documentation update', () => {
    it('should document auto-update in RELEASE-RUNBOOK.md', () => {
      const runbookPath = join(REPO_ROOT, 'RELEASE-RUNBOOK.md');
      expect(existsSync(runbookPath)).toBe(true);
      
      const runbookContent = readFileSync(runbookPath, 'utf8');
      
      // Should mention deployed state auto-update
      expect(runbookContent).toContain('deployed.<environment>.*');
      expect(runbookContent).toContain('auto-updated after successful deployment');
    });
  });

  describe('Workflow Integration Tests', () => {
    it('should use correct git identity for commits', () => {
      const workflows = ['deploy-metagraph.yml', 'deploy-services.yml'];
      
      workflows.forEach(workflowFile => {
        const workflowPath = join(WORKFLOWS_DIR, workflowFile);
        const workflowContent = readFileSync(workflowPath, 'utf8');
        const workflow = load(workflowContent);
        
        const updateJob = workflow.jobs['update-deployed-state'];
        const steps = updateJob.steps;
        
        const configStep = steps.find(step => 
          step.name && step.name.includes('Configure Git')
        );
        expect(configStep).toBeTruthy();
        
        // Should use OttoBot identity
        expect(configStep.run).toContain('OttoBot');
        expect(configStep.run).toContain('ottobot@kd5ujc.xyz');
      });
    });

    it('should validate yq is available', () => {
      const workflows = ['deploy-metagraph.yml', 'deploy-services.yml'];
      
      workflows.forEach(workflowFile => {
        const workflowPath = join(WORKFLOWS_DIR, workflowFile);
        const workflowContent = readFileSync(workflowPath, 'utf8');
        const workflow = load(workflowContent);
        
        const updateJob = workflow.jobs['update-deployed-state'];
        
        // Should run on ubuntu-latest which has yq available
        expect(updateJob['runs-on']).toBe('ubuntu-latest');
      });
    });
  });

  describe('versions.yaml structure validation', () => {
    it('should have the correct deployed.scratch structure', () => {
      const versionsPath = join(REPO_ROOT, 'versions.yaml');
      expect(existsSync(versionsPath)).toBe(true);
      
      const versionsContent = readFileSync(versionsPath, 'utf8');
      const versions = load(versionsContent);
      
      // Should have deployed.scratch section
      expect(versions.deployed).toBeTruthy();
      expect(versions.deployed.scratch).toBeTruthy();
      
      // Should have all required fields (initially empty)
      const deployedScratch = versions.deployed.scratch;
      expect(deployedScratch).toHaveProperty('ottochain');
      expect(deployedScratch).toHaveProperty('services');
      expect(deployedScratch).toHaveProperty('explorer');
      expect(deployedScratch).toHaveProperty('monitoring');
      expect(deployedScratch).toHaveProperty('timestamp');
      expect(deployedScratch).toHaveProperty('workflow_run');
    });
  });
});