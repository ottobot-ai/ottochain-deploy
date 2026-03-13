/**
 * TDD Tests for npm to pnpm Migration
 * Card: 69b374c87221b476bc47fe5d
 * 
 * These tests MUST FAIL initially to prove TDD approach.
 * They verify the migration from npm to pnpm according to specification.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync, existsSync } from 'fs';
import { load } from 'js-yaml';
import { join } from 'path';

const REPO_ROOT = process.cwd();
const WORKFLOWS_DIR = join(REPO_ROOT, '.github/workflows');

describe('npm to pnpm Migration - TDD Tests', () => {
  describe('Lockfile Migration', () => {
    it('should remove npm lockfile (package-lock.json)', () => {
      const npmLockPath = join(REPO_ROOT, 'package-lock.json');
      
      // This WILL FAIL initially - package-lock.json exists
      expect(existsSync(npmLockPath)).toBe(false);
    });

    it('should have pnpm lockfile (pnpm-lock.yaml)', () => {
      const pnpmLockPath = join(REPO_ROOT, 'pnpm-lock.yaml');
      
      // This WILL FAIL initially - pnpm-lock.yaml doesn't exist
      expect(existsSync(pnpmLockPath)).toBe(true);
    });

    it('should have valid pnpm lockfile format', () => {
      const pnpmLockPath = join(REPO_ROOT, 'pnpm-lock.yaml');
      expect(existsSync(pnpmLockPath)).toBe(true);
      
      const lockContent = readFileSync(pnpmLockPath, 'utf8');
      const lockData = load(lockContent);
      
      // Should have pnpm lockfile version marker
      expect(lockData).toHaveProperty('lockfileVersion');
      expect(lockData.lockfileVersion).toMatch(/^[6-9]\.\d+$/); // pnpm v8+ uses lockfileVersion 6+
    });
  });

  describe('.gitignore Updates', () => {
    it('should include package-lock.json in .gitignore', () => {
      const gitignorePath = join(REPO_ROOT, '.gitignore');
      expect(existsSync(gitignorePath)).toBe(true);
      
      const gitignoreContent = readFileSync(gitignorePath, 'utf8');
      
      // This WILL FAIL initially - package-lock.json not in .gitignore
      expect(gitignoreContent).toContain('package-lock.json');
    });

    it('should not exclude pnpm-lock.yaml from version control', () => {
      const gitignorePath = join(REPO_ROOT, '.gitignore');
      const gitignoreContent = readFileSync(gitignorePath, 'utf8');
      
      // pnpm-lock.yaml should be committed (not in .gitignore)
      expect(gitignoreContent).not.toContain('pnpm-lock.yaml');
    });
  });

  describe('CI Workflow Migration', () => {
    it('should use pnpm in smoke-test.yml workflow', () => {
      const workflowPath = join(WORKFLOWS_DIR, 'smoke-test.yml');
      expect(existsSync(workflowPath)).toBe(true);
      
      const workflowContent = readFileSync(workflowPath, 'utf8');
      
      // This WILL FAIL initially - workflow uses npm
      expect(workflowContent).not.toContain('npm init');
      expect(workflowContent).not.toContain('npm install');
      
      // Should use pnpm instead
      expect(workflowContent).toContain('pnpm install');
    });

    it('should use pnpm in validate-versions.yml workflow', () => {
      const workflowPath = join(WORKFLOWS_DIR, 'validate-versions.yml');
      expect(existsSync(workflowPath)).toBe(true);
      
      const workflowContent = readFileSync(workflowPath, 'utf8');
      
      // This WILL FAIL initially - workflow uses npm install -g
      expect(workflowContent).not.toContain('npm install -g semver');
      
      // Should use pnpm add -g instead
      expect(workflowContent).toContain('pnpm add -g semver');
    });

    it('should maintain existing pnpm usage in deploy-layers.yml', () => {
      const workflowPath = join(WORKFLOWS_DIR, 'deploy-layers.yml');
      expect(existsSync(workflowPath)).toBe(true);
      
      const workflowContent = readFileSync(workflowPath, 'utf8');
      
      // Should still have pnpm (this should pass as it's already correct)
      expect(workflowContent).toContain('pnpm install --frozen-lockfile');
      expect(workflowContent).toContain('pnpm run build');
      expect(workflowContent).toContain('pnpm start');
    });

    it('should have pnpm setup step in workflows that install packages', () => {
      const workflowsWithInstall = ['smoke-test.yml', 'validate-versions.yml'];
      
      workflowsWithInstall.forEach(workflowFile => {
        const workflowPath = join(WORKFLOWS_DIR, workflowFile);
        const workflowContent = readFileSync(workflowPath, 'utf8');
        const workflow = load(workflowContent);
        
        // Should have a job that sets up pnpm
        const hasJobWithPnpmSetup = Object.values(workflow.jobs).some(job => {
          return job.steps && job.steps.some(step => 
            step.name && step.name.includes('pnpm') ||
            step.uses && step.uses.includes('pnpm/action-setup')
          );
        });
        
        // This WILL FAIL initially - no pnpm setup
        expect(hasJobWithPnpmSetup).toBe(true);
      });
    });
  });

  describe('Package.json Scripts Compatibility', () => {
    it('should maintain all existing npm scripts', () => {
      const packagePath = join(REPO_ROOT, 'package.json');
      expect(existsSync(packagePath)).toBe(true);
      
      const packageContent = readFileSync(packagePath, 'utf8');
      const packageData = JSON.parse(packageContent);
      
      // Scripts should remain unchanged (they work with both npm and pnpm)
      expect(packageData.scripts).toHaveProperty('test');
      expect(packageData.scripts).toHaveProperty('test:watch');
      expect(packageData.scripts.test).toBe('vitest run');
      expect(packageData.scripts['test:watch']).toBe('vitest');
    });

    it('should work with pnpm run commands', async () => {
      // This tests that pnpm can execute the scripts
      // This WILL FAIL initially if pnpm lockfile doesn't exist
      
      const packagePath = join(REPO_ROOT, 'package.json');
      const packageData = JSON.parse(readFileSync(packagePath, 'utf8'));
      
      // If we have a pnpm-lock.yaml, the scripts should be executable with pnpm
      const pnpmLockExists = existsSync(join(REPO_ROOT, 'pnpm-lock.yaml'));
      if (pnpmLockExists) {
        // pnpm should be able to run the test script
        // Note: In real scenario, we'd exec `pnpm run test --dry-run` here
        // but for unit test, we just check the structure is compatible
        expect(packageData.scripts.test).toBeTruthy();
        expect(packageData.scripts.test).not.toContain('npm');
      }
      
      expect(pnpmLockExists).toBe(true);
    });
  });

  describe('Dependencies and Node_modules', () => {
    it('should have node_modules structure created by pnpm', async () => {
      // pnpm creates a different node_modules structure with .pnpm directory
      const pnpmDir = join(REPO_ROOT, 'node_modules', '.pnpm');
      
      // This WILL FAIL initially - current node_modules created by npm
      expect(existsSync(pnpmDir)).toBe(true);
    });

    it('should maintain all dev dependencies', () => {
      const packagePath = join(REPO_ROOT, 'package.json');
      const packageData = JSON.parse(readFileSync(packagePath, 'utf8'));
      
      // All existing dependencies should be preserved
      expect(packageData.devDependencies).toHaveProperty('@types/js-yaml');
      expect(packageData.devDependencies).toHaveProperty('@types/node');
      expect(packageData.devDependencies).toHaveProperty('js-yaml');
      expect(packageData.devDependencies).toHaveProperty('vitest');
    });
  });

  describe('Migration Verification', () => {
    it('should not have any npm-specific artifacts remaining', () => {
      // After migration, no npm lockfile should exist
      const npmLockPath = join(REPO_ROOT, 'package-lock.json');
      expect(existsSync(npmLockPath)).toBe(false);
      
      // No npm shrinkwrap
      const shrinkwrapPath = join(REPO_ROOT, 'npm-shrinkwrap.json');
      expect(existsSync(shrinkwrapPath)).toBe(false);
    });

    it('should work end-to-end with test scripts', () => {
      // Verify the migration is complete and functional
      const pnpmLockPath = join(REPO_ROOT, 'pnpm-lock.yaml');
      const packageLockPath = join(REPO_ROOT, 'package-lock.json');
      const gitignorePath = join(REPO_ROOT, '.gitignore');
      
      // All migration criteria met
      expect(existsSync(pnpmLockPath)).toBe(true);
      expect(existsSync(packageLockPath)).toBe(false);
      
      const gitignoreContent = readFileSync(gitignorePath, 'utf8');
      expect(gitignoreContent).toContain('package-lock.json');
    });
  });

  describe('Makefile Compatibility', () => {
    it('should work with existing Makefile if it references npm', () => {
      const makefilePath = join(REPO_ROOT, 'Makefile');
      if (existsSync(makefilePath)) {
        const makefileContent = readFileSync(makefilePath, 'utf8');
        
        // If Makefile uses npm commands, they should be updated to pnpm
        // This would FAIL if Makefile still has npm references after migration
        if (makefileContent.includes('install') || makefileContent.includes('test')) {
          expect(makefileContent).not.toContain('npm install');
          expect(makefileContent).not.toContain('npm run');
          expect(makefileContent).not.toContain('npm test');
        }
      }
    });
  });
});