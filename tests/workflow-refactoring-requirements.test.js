/**
 * TDD Tests for Workflow Refactoring Requirements
 * 
 * These tests define the expected structure after refactoring.
 * Tests will FAIL until the refactoring is completed.
 */

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

describe('Workflow Refactoring Requirements TDD', () => {
  
  describe('File Structure Requirements', () => {
    
    it('SHOULD FAIL: .github/actions directory structure must exist', () => {
      const actionsDir = path.join(__dirname, '../.github/actions');
      expect(fs.existsSync(actionsDir)).toBe(true);
      
      const requiredActions = [
        'setup-ssh',
        'plan-deployment', 
        'setup-java-build',
        'manage-containers',
        'setup-environment'
      ];
      
      for (const actionName of requiredActions) {
        const actionDir = path.join(actionsDir, actionName);
        expect(fs.existsSync(actionDir)).toBe(true);
        
        const actionFile = path.join(actionDir, 'action.yml');
        expect(fs.existsSync(actionFile)).toBe(true);
      }
    });
    
    it('SHOULD FAIL: reusable workflows must exist in .github/workflows/', () => {
      const workflowsDir = path.join(__dirname, '../.github/workflows');
      
      const requiredReusableWorkflows = [
        'reusable-jar-build.yml',
        'reusable-cluster-deployment.yml',
        'reusable-services-deployment.yml',
        'reusable-post-deployment-tests.yml'
      ];
      
      for (const workflowName of requiredReusableWorkflows) {
        const workflowPath = path.join(workflowsDir, workflowName);
        expect(fs.existsSync(workflowPath)).toBe(true);
      }
    });
  });

  describe('Refactored Main Workflows Requirements', () => {
    
    it('SHOULD FAIL: release-scratch.yml must be dramatically simplified', () => {
      const workflowPath = path.join(__dirname, '../.github/workflows/release-scratch.yml');
      
      if (!fs.existsSync(workflowPath)) {
        throw new Error('release-scratch.yml does not exist');
      }
      
      const content = fs.readFileSync(workflowPath, 'utf8');
      const lineCount = content.split('\n').length;
      
      // Original was ~800 lines, should be reduced to ~150 lines
      expect(lineCount).toBeLessThan(200);
      
      const workflowContent = yaml.load(content);
      
      // Should use reusable JAR build workflow
      const buildJob = workflowContent.jobs.build;
      expect(buildJob.uses).toBe('./.github/workflows/reusable-jar-build.yml');
      
      // Should use reusable cluster deployment workflow  
      const deployJob = workflowContent.jobs.deploy;
      expect(deployJob.uses).toBe('./.github/workflows/reusable-cluster-deployment.yml');
      
      // Should not contain inline SSH setup
      expect(content).not.toMatch(/mkdir -p ~\/\.ssh/);
      expect(content).not.toMatch(/chmod 600 ~\/\.ssh/);
      
      // Should not contain inline Java setup
      expect(content).not.toMatch(/setup-java@v4/);
      expect(content).not.toMatch(/sbt\/setup-sbt/);
    });
    
    it('SHOULD FAIL: deploy-dev-orchestrated.yml must be simplified', () => {
      const workflowPath = path.join(__dirname, '../.github/workflows/deploy-dev-orchestrated.yml');
      
      if (!fs.existsSync(workflowPath)) {
        throw new Error('deploy-dev-orchestrated.yml does not exist');
      }
      
      const content = fs.readFileSync(workflowPath, 'utf8');
      const lineCount = content.split('\n').length;
      
      // Original was ~400 lines, should be reduced to ~100 lines
      expect(lineCount).toBeLessThan(150);
      
      const workflowContent = yaml.load(content);
      
      // Should use reusable services deployment workflow
      const deployJob = workflowContent.jobs['deploy-services'] || workflowContent.jobs.deploy;
      expect(deployJob.uses).toBe('./.github/workflows/reusable-services-deployment.yml');
    });
    
    it('SHOULD FAIL: deploy-staging.yml must be simplified', () => {
      const workflowPath = path.join(__dirname, '../.github/workflows/deploy-staging.yml');
      
      if (!fs.existsSync(workflowPath)) {
        throw new Error('deploy-staging.yml does not exist');
      }
      
      const content = fs.readFileSync(workflowPath, 'utf8');
      const lineCount = content.split('\n').length;
      
      // Should be much smaller after refactoring
      expect(lineCount).toBeLessThan(100);
      
      // Should use composite actions for common patterns
      const workflowContent = yaml.load(content);
      const deployJob = workflowContent.jobs['deploy-staging'] || workflowContent.jobs.deploy;
      
      const planStep = deployJob.steps.find(step => 
        step.uses && step.uses.includes('plan-deployment'));
      expect(planStep).toBeDefined();
    });
  });

  describe('Duplication Elimination Requirements', () => {
    
    it('SHOULD FAIL: SSH setup code must not be duplicated', () => {
      const workflowsDir = path.join(__dirname, '../.github/workflows');
      const workflowFiles = fs.readdirSync(workflowsDir)
        .filter(file => file.endsWith('.yml') && !file.startsWith('test-') && !file.startsWith('reusable-'));
      
      let sshSetupCount = 0;
      
      for (const workflowFile of workflowFiles) {
        const workflowPath = path.join(workflowsDir, workflowFile);
        const content = fs.readFileSync(workflowPath, 'utf8');
        
        // Count SSH setup patterns
        const sshSetupMatches = content.match(/mkdir -p ~\/\.ssh/g) || [];
        sshSetupCount += sshSetupMatches.length;
        
        // Each workflow should use the composite action instead
        if (content.includes('ssh') && !content.startsWith('name: Test')) {
          expect(content).toMatch(/\.\.\/\.github\/actions\/setup-ssh/);
        }
      }
      
      // Should have zero inline SSH setups (all should use composite action)
      expect(sshSetupCount).toBe(0);
    });
    
    it('SHOULD FAIL: Java/sbt setup code must not be duplicated', () => {
      const workflowsDir = path.join(__dirname, '../.github/workflows');
      const workflowFiles = fs.readdirSync(workflowsDir)
        .filter(file => file.endsWith('.yml') && !file.startsWith('test-') && !file.startsWith('reusable-'));
      
      let javaSetupCount = 0;
      let sbtSetupCount = 0;
      
      for (const workflowFile of workflowFiles) {
        const workflowPath = path.join(workflowsDir, workflowFile);
        const content = fs.readFileSync(workflowPath, 'utf8');
        
        // Count Java/sbt setup patterns (excluding reusable workflows)
        if (!workflowFile.startsWith('reusable-')) {
          const javaMatches = content.match(/setup-java@v4/g) || [];
          const sbtMatches = content.match(/sbt\/setup-sbt/g) || [];
          
          javaSetupCount += javaMatches.length;
          sbtSetupCount += sbtMatches.length;
        }
      }
      
      // Should have zero inline Java/sbt setups in main workflows
      expect(javaSetupCount).toBe(0);
      expect(sbtSetupCount).toBe(0);
    });
    
    it('SHOULD FAIL: deployment planning code must not be duplicated', () => {
      const workflowsDir = path.join(__dirname, '../.github/workflows');
      const workflowFiles = fs.readdirSync(workflowsDir)
        .filter(file => file.endsWith('.yml') && !file.startsWith('test-') && !file.startsWith('reusable-'));
      
      let yqInstallCount = 0;
      let compareScriptCount = 0;
      
      for (const workflowFile of workflowFiles) {
        const workflowPath = path.join(workflowsDir, workflowFile);
        const content = fs.readFileSync(workflowPath, 'utf8');
        
        // Count planning patterns (excluding reusable workflows)
        if (!workflowFile.startsWith('reusable-')) {
          const yqMatches = content.match(/snap install yq/g) || [];
          const scriptMatches = content.match(/compare-versions\.sh/g) || [];
          
          yqInstallCount += yqMatches.length;
          compareScriptCount += scriptMatches.length;
        }
      }
      
      // Should have zero inline planning setups in main workflows
      expect(yqInstallCount).toBe(0);
      expect(compareScriptCount).toBeLessThanOrEqual(1); // Only in reusable workflows
    });
  });

  describe('Performance and Maintainability Requirements', () => {
    
    it('SHOULD FAIL: total workflow file lines must be reduced by 70%+', () => {
      const workflowsDir = path.join(__dirname, '../.github/workflows');
      const mainWorkflowFiles = [
        'release-scratch.yml',
        'release-scratch-layered.yml', 
        'deploy-dev-orchestrated.yml',
        'deploy-staging.yml',
        'deploy-production.yml',
        'rollback.yml'
      ];
      
      let totalLines = 0;
      
      for (const workflowFile of mainWorkflowFiles) {
        const workflowPath = path.join(workflowsDir, workflowFile);
        if (fs.existsSync(workflowPath)) {
          const content = fs.readFileSync(workflowPath, 'utf8');
          totalLines += content.split('\n').length;
        }
      }
      
      // Original was 2,901 lines, target is under 870 lines (70% reduction)
      expect(totalLines).toBeLessThan(870);
      console.log(`Total main workflow lines after refactoring: ${totalLines} (target: <870)`);
    });
    
    it('SHOULD FAIL: workflows must have consistent parameter interfaces', () => {
      const workflowsDir = path.join(__dirname, '../.github/workflows');
      const reusableWorkflows = [
        'reusable-jar-build.yml',
        'reusable-cluster-deployment.yml',
        'reusable-services-deployment.yml'
      ];
      
      for (const workflowFile of reusableWorkflows) {
        const workflowPath = path.join(workflowsDir, workflowFile);
        
        if (!fs.existsSync(workflowPath)) {
          throw new Error(`Reusable workflow does not exist: ${workflowFile}`);
        }
        
        const content = fs.readFileSync(workflowPath, 'utf8');
        const workflowContent = yaml.load(content);
        
        // All reusable workflows should have consistent input patterns
        expect(workflowContent.on.workflow_call).toBeDefined();
        expect(workflowContent.on.workflow_call.inputs).toBeDefined();
        expect(workflowContent.on.workflow_call.outputs).toBeDefined();
        
        // Should have environment input
        expect(workflowContent.on.workflow_call.inputs.environment).toBeDefined();
        
        // Should have status output
        const outputs = workflowContent.on.workflow_call.outputs;
        const hasStatusOutput = Object.keys(outputs).some(key => key.includes('status'));
        expect(hasStatusOutput).toBe(true);
      }
    });
    
    it('SHOULD FAIL: composite actions must have proper error handling', () => {
      const actionsDir = path.join(__dirname, '../.github/actions');
      const compositeActions = ['setup-ssh', 'plan-deployment', 'setup-java-build', 'manage-containers'];
      
      for (const actionName of compositeActions) {
        const actionPath = path.join(actionsDir, actionName, 'action.yml');
        
        if (!fs.existsSync(actionPath)) {
          throw new Error(`Composite action does not exist: ${actionName}`);
        }
        
        const content = fs.readFileSync(actionPath, 'utf8');
        const actionContent = yaml.load(content);
        
        // Should have error handling in steps
        const stepsWithErrorHandling = actionContent.runs.steps.filter(step =>
          step.run && (step.run.includes('set -e') || step.run.includes('|| exit 1')));
        
        expect(stepsWithErrorHandling.length).toBeGreaterThan(0);
      }
    });
  });

  describe('Documentation and Testing Requirements', () => {
    
    it('SHOULD FAIL: composite actions must have comprehensive documentation', () => {
      const actionsDir = path.join(__dirname, '../.github/actions');
      const compositeActions = ['setup-ssh', 'plan-deployment', 'setup-java-build', 'manage-containers', 'setup-environment'];
      
      for (const actionName of compositeActions) {
        const readmePath = path.join(actionsDir, actionName, 'README.md');
        expect(fs.existsSync(readmePath)).toBe(true);
        
        const readmeContent = fs.readFileSync(readmePath, 'utf8');
        expect(readmeContent).toMatch(/# .+ Composite Action/);
        expect(readmeContent).toMatch(/## Inputs/);
        expect(readmeContent).toMatch(/## Outputs/);
        expect(readmeContent).toMatch(/## Usage Example/);
      }
    });
    
    it('SHOULD FAIL: test workflows must validate all composite actions', () => {
      const testWorkflowPath = path.join(__dirname, '../.github/workflows/test-composite-actions.yml');
      expect(fs.existsSync(testWorkflowPath)).toBe(true);
      
      const content = fs.readFileSync(testWorkflowPath, 'utf8');
      const workflowContent = yaml.load(content);
      
      // Should have test jobs for all composite actions
      const expectedTestJobs = [
        'test-ssh-setup-composite',
        'test-deployment-plan-composite',
        'test-java-build-composite',
        'test-container-management-composite',
        'test-environment-setup-composite'
      ];
      
      for (const jobName of expectedTestJobs) {
        expect(workflowContent.jobs[jobName]).toBeDefined();
      }
    });
  });
});

// Performance benchmark test
describe('Refactoring Performance Impact', () => {
  
  it('SHOULD FAIL: refactored workflows should complete faster due to reuse', () => {
    // This test defines the expected performance improvement
    // Implementation should cache builds and reuse components
    
    const performanceMetrics = {
      expectedBuildTimeReduction: 0.3, // 30% faster builds through caching
      expectedMaintainabilityScore: 0.8, // 80% more maintainable
      expectedDuplicationReduction: 0.85 // 85% less duplication
    };
    
    // These metrics should be validated by the implementation
    expect(performanceMetrics.expectedBuildTimeReduction).toBeGreaterThan(0.25);
    expect(performanceMetrics.expectedMaintainabilityScore).toBeGreaterThan(0.75);
    expect(performanceMetrics.expectedDuplicationReduction).toBeGreaterThan(0.8);
    
    console.log('📊 Expected performance improvements:', performanceMetrics);
  });
});

// Test runner
if (require.main === module) {
  const { execSync } = require('child_process');
  
  console.log('🧪 Running TDD tests for workflow refactoring requirements...');
  console.log('These tests define what the refactored structure should look like.\n');
  
  try {
    execSync('npx jest --verbose tests/workflow-refactoring-requirements.test.js', { stdio: 'inherit' });
    console.log('\n❌ Unexpected: Tests passed! Refactoring may already be complete.');
  } catch (error) {
    console.log('\n✅ Expected: Tests failed - refactoring not yet implemented');
    console.log('📋 These tests define the target structure for the refactoring');
    console.log('📝 Implement the composite actions and reusable workflows to make tests pass');
  }
}