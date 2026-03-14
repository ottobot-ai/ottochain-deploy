import { describe, it, expect } from 'vitest';
import { existsSync, readFileSync } from 'fs';
import { join } from 'path';
import { execSync } from 'child_process';
import { globSync } from 'glob';

const ROOT_DIR = join(process.cwd());

describe('PNPM Migration', () => {
  describe('Package Lock Files', () => {
    it('should remove package-lock.json', () => {
      const packageLockPath = join(ROOT_DIR, 'package-lock.json');
      expect(existsSync(packageLockPath)).toBe(false);
    });

    it('should have pnpm-lock.yaml', () => {
      const pnpmLockPath = join(ROOT_DIR, 'pnpm-lock.yaml');
      expect(existsSync(pnpmLockPath)).toBe(true);
    });

    it('should have valid pnpm lockfile format', () => {
      const pnpmLockPath = join(ROOT_DIR, 'pnpm-lock.yaml');
      if (existsSync(pnpmLockPath)) {
        const content = readFileSync(pnpmLockPath, 'utf8');
        expect(content).toContain('lockfileVersion:');
        expect(content).toContain('dependencies:');
      }
    });
  });

  describe('Gitignore Configuration', () => {
    it('should exclude package-lock.json in .gitignore', () => {
      const gitignorePath = join(ROOT_DIR, '.gitignore');
      expect(existsSync(gitignorePath)).toBe(true);
      
      const content = readFileSync(gitignorePath, 'utf8');
      expect(content).toMatch(/package-lock\.json/);
    });

    it('should not exclude pnpm-lock.yaml in .gitignore', () => {
      const gitignorePath = join(ROOT_DIR, '.gitignore');
      const content = readFileSync(gitignorePath, 'utf8');
      // pnpm-lock.yaml should NOT be in .gitignore
      expect(content).not.toMatch(/pnpm-lock\.yaml/);
    });
  });

  describe('CI Workflows', () => {
    it('should use pnpm instead of npm in all GitHub workflows', () => {
      const workflowFiles = globSync('.github/workflows/*.yml', { cwd: ROOT_DIR });
      
      for (const file of workflowFiles) {
        const content = readFileSync(join(ROOT_DIR, file), 'utf8');
        
        // Check for npm commands that should be replaced
        expect(content).not.toMatch(/npm install(?!\s+pnpm)/);
        expect(content).not.toMatch(/npm init(?!\s+pnpm)/);
        expect(content).not.toMatch(/npm run/);
        expect(content).not.toMatch(/npm ci/);
        
        // If the workflow installs packages, it should use pnpm
        if (content.includes('install playwright') || content.includes('package.json')) {
          expect(content).toMatch(/pnpm install|pnpm|npm install pnpm/);
        }
      }
    });

    it('should have pnpm setup in workflows that install packages', () => {
      const workflowFiles = globSync('.github/workflows/*.yml', { cwd: ROOT_DIR });
      
      for (const file of workflowFiles) {
        const content = readFileSync(join(ROOT_DIR, file), 'utf8');
        
        // If workflow has package installation, should setup pnpm
        if (content.includes('install') && content.includes('node')) {
          // Should either use corepack or install pnpm
          const hasPnpmSetup = content.includes('corepack enable') || 
                              content.includes('npm install -g pnpm') ||
                              content.includes('pnpm/action-setup') ||
                              content.includes('npm install pnpm');
          
          if (content.includes('package.json') || content.includes('node_modules')) {
            expect(hasPnpmSetup).toBe(true);
          }
        }
      }
    });
  });

  describe('GitHub Actions', () => {
    it('should use pnpm in custom actions that install packages', () => {
      const actionFiles = globSync('.github/actions/**/action.yml', { cwd: ROOT_DIR });
      
      for (const file of actionFiles) {
        const content = readFileSync(join(ROOT_DIR, file), 'utf8');
        
        // Check for npm commands that should be replaced
        expect(content).not.toMatch(/npm install(?!\s+pnpm)/);
        expect(content).not.toMatch(/npm ci/);
        expect(content).not.toMatch(/npm run/);
      }
    });
  });

  describe('Package Scripts Functionality', () => {
    it('should have all package.json scripts work with pnpm', () => {
      const packageJsonPath = join(ROOT_DIR, 'package.json');
      expect(existsSync(packageJsonPath)).toBe(true);
      
      const packageJson = JSON.parse(readFileSync(packageJsonPath, 'utf8'));
      
      if (packageJson.scripts) {
        for (const [scriptName, scriptCommand] of Object.entries(packageJson.scripts)) {
          expect(() => {
            // Test that pnpm can find and parse the script
            const output = execSync(`pnpm run ${scriptName} --dry-run`, { 
              cwd: ROOT_DIR,
              encoding: 'utf8',
              stdio: 'pipe'
            });
            // Should not error and should mention the script
            expect(output).toBeTruthy();
          }).not.toThrow();
        }
      }
    });

    it('should have working pnpm installation', () => {
      expect(() => {
        execSync('pnpm --version', { cwd: ROOT_DIR, stdio: 'pipe' });
      }).not.toThrow();
    });

    it('should be able to install dependencies with pnpm', () => {
      expect(() => {
        // Test that pnpm install works (use --frozen-lockfile for dry run)
        execSync('pnpm install --frozen-lockfile', { 
          cwd: ROOT_DIR, 
          stdio: 'pipe' 
        });
      }).not.toThrow();
    });
  });

  describe('Lockfile Integrity', () => {
    it('should have lockfile that matches package.json', () => {
      const packageJsonPath = join(ROOT_DIR, 'package.json');
      const pnpmLockPath = join(ROOT_DIR, 'pnpm-lock.yaml');
      
      if (existsSync(packageJsonPath) && existsSync(pnpmLockPath)) {
        const packageJson = JSON.parse(readFileSync(packageJsonPath, 'utf8'));
        const lockContent = readFileSync(pnpmLockPath, 'utf8');
        
        // Check that all dependencies from package.json are in lockfile
        const allDeps = {
          ...packageJson.dependencies,
          ...packageJson.devDependencies,
          ...packageJson.peerDependencies,
          ...packageJson.optionalDependencies
        };
        
        for (const depName of Object.keys(allDeps || {})) {
          expect(lockContent).toContain(depName);
        }
      }
    });
  });

  describe('Documentation Updates', () => {
    it('should update README.md if it mentions npm', () => {
      const readmePath = join(ROOT_DIR, 'README.md');
      
      if (existsSync(readmePath)) {
        const content = readFileSync(readmePath, 'utf8');
        
        // If README mentions package management, should mention pnpm
        if (content.includes('install') || content.includes('dependencies')) {
          const npmReferences = content.match(/npm install|npm run|npm ci/g) || [];
          const pnpmReferences = content.match(/pnpm install|pnpm run|pnpm/g) || [];
          
          // Should have more pnpm references than npm, or no npm references
          if (npmReferences.length > 0) {
            expect(pnpmReferences.length).toBeGreaterThanOrEqual(npmReferences.length);
          }
        }
      }
    });
  });
});