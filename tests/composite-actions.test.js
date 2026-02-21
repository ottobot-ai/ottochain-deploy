/**
 * TDD Tests for Composite Actions Structure (Node.js)
 * 
 * These tests will FAIL until the composite actions are implemented.
 * Tests define the expected structure and behavior of each composite action.
 */

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

describe('Composite Actions TDD Tests', () => {
  const actionsDir = path.join(__dirname, '../.github/actions');

  describe('setup-ssh composite action', () => {
    const actionPath = path.join(actionsDir, 'setup-ssh', 'action.yml');

    it('SHOULD FAIL: setup-ssh/action.yml must exist', () => {
      expect(fs.existsSync(actionPath)).toBe(true);
    });

    it('SHOULD FAIL: setup-ssh action must have correct structure', () => {
      if (!fs.existsSync(actionPath)) {
        throw new Error('Action file does not exist - expected failure');
      }

      const actionContent = yaml.load(fs.readFileSync(actionPath, 'utf8'));
      
      expect(actionContent.name).toBe('Setup SSH for Hetzner Nodes');
      expect(actionContent.description).toContain('Configure SSH access to Hetzner nodes');
      
      // Required inputs
      expect(actionContent.inputs.hetzner_ssh_key).toBeDefined();
      expect(actionContent.inputs.hetzner_ssh_key.required).toBe(true);
      expect(actionContent.inputs.node1_ip).toBeDefined();
      expect(actionContent.inputs.node2_ip).toBeDefined();
      expect(actionContent.inputs.node3_ip).toBeDefined();
      expect(actionContent.inputs.services_ip).toBeDefined();
      
      expect(actionContent.runs.using).toBe('composite');
      expect(actionContent.runs.steps).toHaveLength(3);
      
      // Step 1: Create SSH directory and key file
      expect(actionContent.runs.steps[0].name).toContain('Create SSH directory');
      expect(actionContent.runs.steps[0].shell).toBe('bash');
      
      // Step 2: Write SSH config
      expect(actionContent.runs.steps[1].name).toContain('Configure SSH hosts');
      
      // Step 3: Set proper permissions
      expect(actionContent.runs.steps[2].name).toContain('Set SSH permissions');
    });
  });

  describe('plan-deployment composite action', () => {
    const actionPath = path.join(actionsDir, 'plan-deployment', 'action.yml');

    it('SHOULD FAIL: plan-deployment/action.yml must exist', () => {
      expect(fs.existsSync(actionPath)).toBe(true);
    });

    it('SHOULD FAIL: plan-deployment action must have correct structure', () => {
      if (!fs.existsSync(actionPath)) {
        throw new Error('Action file does not exist - expected failure');
      }

      const actionContent = yaml.load(fs.readFileSync(actionPath, 'utf8'));
      
      expect(actionContent.name).toBe('Plan Deployment Changes');
      expect(actionContent.description).toContain('Analyze and plan deployment changes');
      
      // Required inputs
      expect(actionContent.inputs.environment).toBeDefined();
      expect(actionContent.inputs.environment.required).toBe(true);
      expect(actionContent.inputs.branch_name).toBeDefined();
      
      // Required outputs
      expect(actionContent.outputs.environment).toBeDefined();
      expect(actionContent.outputs.plan_file).toBeDefined();
      expect(actionContent.outputs.changes_detected).toBeDefined();
      
      expect(actionContent.runs.using).toBe('composite');
      expect(actionContent.runs.steps.length).toBeGreaterThanOrEqual(3);
      
      // Should install yq
      const yqStep = actionContent.runs.steps.find(step => 
        step.run && step.run.includes('snap install yq'));
      expect(yqStep).toBeDefined();
      
      // Should run comparison script
      const compareStep = actionContent.runs.steps.find(step =>
        step.run && step.run.includes('compare-versions.sh'));
      expect(compareStep).toBeDefined();
    });
  });

  describe('setup-java-build composite action', () => {
    const actionPath = path.join(actionsDir, 'setup-java-build', 'action.yml');

    it('SHOULD FAIL: setup-java-build/action.yml must exist', () => {
      expect(fs.existsSync(actionPath)).toBe(true);
    });

    it('SHOULD FAIL: setup-java-build action must have correct structure', () => {
      if (!fs.existsSync(actionPath)) {
        throw new Error('Action file does not exist - expected failure');
      }

      const actionContent = yaml.load(fs.readFileSync(actionPath, 'utf8'));
      
      expect(actionContent.name).toBe('Setup Java Build Environment');
      expect(actionContent.description).toContain('Setup Java, sbt, and checkout repositories');
      
      // Required inputs
      expect(actionContent.inputs.java_version).toBeDefined();
      expect(actionContent.inputs.java_version.default).toBe('21');
      expect(actionContent.inputs.tessellation_version).toBeDefined();
      
      // Optional inputs
      expect(actionContent.inputs.apply_tessellation_patch).toBeDefined();
      expect(actionContent.inputs.apply_tessellation_patch.default).toBe('true');
      
      expect(actionContent.runs.using).toBe('composite');
      expect(actionContent.runs.steps.length).toBeGreaterThanOrEqual(5);
      
      // Should checkout ottochain
      const ottochainStep = actionContent.runs.steps.find(step =>
        step.uses === 'actions/checkout@v4' && step.with && step.with.repository === 'ottobot-ai/ottochain');
      expect(ottochainStep).toBeDefined();
      
      // Should checkout tessellation
      const tessellationStep = actionContent.runs.steps.find(step =>
        step.uses === 'actions/checkout@v4' && step.with && step.with.repository === 'Constellation-Labs/tessellation');
      expect(tessellationStep).toBeDefined();
      
      // Should setup Java
      const javaStep = actionContent.runs.steps.find(step =>
        step.uses === 'actions/setup-java@v4');
      expect(javaStep).toBeDefined();
      
      // Should setup sbt
      const sbtStep = actionContent.runs.steps.find(step =>
        step.uses === 'sbt/setup-sbt@v1');
      expect(sbtStep).toBeDefined();
    });
  });

  describe('manage-containers composite action', () => {
    const actionPath = path.join(actionsDir, 'manage-containers', 'action.yml');

    it('SHOULD FAIL: manage-containers/action.yml must exist', () => {
      expect(fs.existsSync(actionPath)).toBe(true);
    });

    it('SHOULD FAIL: manage-containers action must have correct structure', () => {
      if (!fs.existsSync(actionPath)) {
        throw new Error('Action file does not exist - expected failure');
      }

      const actionContent = yaml.load(fs.readFileSync(actionPath, 'utf8'));
      
      expect(actionContent.name).toBe('Manage Docker Containers');
      expect(actionContent.description).toContain('Start, stop, or restart Docker containers');
      
      // Required inputs
      expect(actionContent.inputs.action).toBeDefined();
      expect(actionContent.inputs.action.required).toBe(true);
      expect(actionContent.inputs.hosts).toBeDefined();
      expect(actionContent.inputs.hosts.required).toBe(true);
      expect(actionContent.inputs.ssh_key).toBeDefined();
      expect(actionContent.inputs.node_ips).toBeDefined();
      
      // Optional inputs
      expect(actionContent.inputs.profiles).toBeDefined();
      expect(actionContent.inputs.compose_file).toBeDefined();
      
      // Outputs
      expect(actionContent.outputs.container_status).toBeDefined();
      expect(actionContent.outputs.affected_containers).toBeDefined();
      
      expect(actionContent.runs.using).toBe('composite');
      expect(actionContent.runs.steps.length).toBeGreaterThanOrEqual(2);
      
      // Should have conditional steps for start/stop
      const conditionalSteps = actionContent.runs.steps.filter(step =>
        step.if && step.if.includes("inputs.action"));
      expect(conditionalSteps.length).toBeGreaterThanOrEqual(2);
    });
  });

  describe('setup-environment composite action', () => {
    const actionPath = path.join(actionsDir, 'setup-environment', 'action.yml');

    it('SHOULD FAIL: setup-environment/action.yml must exist', () => {
      expect(fs.existsSync(actionPath)).toBe(true);
    });

    it('SHOULD FAIL: setup-environment action must have correct structure', () => {
      if (!fs.existsSync(actionPath)) {
        throw new Error('Action file does not exist - expected failure');
      }

      const actionContent = yaml.load(fs.readFileSync(actionPath, 'utf8'));
      
      expect(actionContent.name).toBe('Setup Environment Configuration');
      expect(actionContent.description).toContain('Configure environment variables and files');
      
      // Required inputs
      expect(actionContent.inputs.environment).toBeDefined();
      expect(actionContent.inputs.environment.required).toBe(true);
      expect(actionContent.inputs.keystore_password).toBeDefined();
      expect(actionContent.inputs.keystore_password.required).toBe(true);
      
      // Optional inputs
      expect(actionContent.inputs.token_id).toBeDefined();
      expect(actionContent.inputs.gl0_peer_id).toBeDefined();
      expect(actionContent.inputs.ml0_peer_id).toBeDefined();
      
      // Outputs
      expect(actionContent.outputs.config_created).toBeDefined();
      expect(actionContent.outputs.env_file_path).toBeDefined();
      
      expect(actionContent.runs.using).toBe('composite');
      expect(actionContent.runs.steps.length).toBeGreaterThanOrEqual(2);
    });
  });
});

describe('Reusable Workflows TDD Tests', () => {
  const workflowsDir = path.join(__dirname, '../.github/workflows');

  describe('reusable-jar-build workflow', () => {
    const workflowPath = path.join(workflowsDir, 'reusable-jar-build.yml');

    it('SHOULD FAIL: reusable-jar-build.yml must exist', () => {
      expect(fs.existsSync(workflowPath)).toBe(true);
    });

    it('SHOULD FAIL: reusable-jar-build workflow must have correct structure', () => {
      if (!fs.existsSync(workflowPath)) {
        throw new Error('Workflow file does not exist - expected failure');
      }

      const workflowContent = yaml.load(fs.readFileSync(workflowPath, 'utf8'));
      
      expect(workflowContent.name).toBe('Reusable JAR Build');
      expect(workflowContent.on.workflow_call).toBeDefined();
      
      // Required inputs
      expect(workflowContent.on.workflow_call.inputs.java_version).toBeDefined();
      expect(workflowContent.on.workflow_call.inputs.tessellation_version).toBeDefined();
      expect(workflowContent.on.workflow_call.inputs.skip_build).toBeDefined();
      
      // Required outputs
      expect(workflowContent.on.workflow_call.outputs.jars_artifact_name).toBeDefined();
      expect(workflowContent.on.workflow_call.outputs.build_status).toBeDefined();
      
      // Should have build job
      expect(workflowContent.jobs.build).toBeDefined();
      expect(workflowContent.jobs.build.name).toBe('Build JARs');
      
      // Should use composite actions
      const steps = workflowContent.jobs.build.steps;
      const javaSetupStep = steps.find(step => step.uses && step.uses.includes('setup-java-build'));
      expect(javaSetupStep).toBeDefined();
      
      // Should upload artifacts
      const uploadStep = steps.find(step => step.uses === 'actions/upload-artifact@v4');
      expect(uploadStep).toBeDefined();
      expect(uploadStep.with.name).toBe('jars');
    });
  });

  describe('reusable-cluster-deployment workflow', () => {
    const workflowPath = path.join(workflowsDir, 'reusable-cluster-deployment.yml');

    it('SHOULD FAIL: reusable-cluster-deployment.yml must exist', () => {
      expect(fs.existsSync(workflowPath)).toBe(true);
    });

    it('SHOULD FAIL: reusable-cluster-deployment workflow must have correct structure', () => {
      if (!fs.existsSync(workflowPath)) {
        throw new Error('Workflow file does not exist - expected failure');
      }

      const workflowContent = yaml.load(fs.readFileSync(workflowPath, 'utf8'));
      
      expect(workflowContent.name).toBe('Reusable Cluster Deployment');
      expect(workflowContent.on.workflow_call).toBeDefined();
      
      // Required inputs
      expect(workflowContent.on.workflow_call.inputs.environment).toBeDefined();
      expect(workflowContent.on.workflow_call.inputs.wipe_state).toBeDefined();
      expect(workflowContent.on.workflow_call.inputs.deployment_strategy).toBeDefined();
      
      // Required secrets
      expect(workflowContent.on.workflow_call.secrets.HETZNER_SSH_KEY).toBeDefined();
      expect(workflowContent.on.workflow_call.secrets.CL_KEYSTORE_PASSWORD).toBeDefined();
      
      // Required outputs
      expect(workflowContent.on.workflow_call.outputs.gl0_peer_id).toBeDefined();
      expect(workflowContent.on.workflow_call.outputs.ml0_peer_id).toBeDefined();
      expect(workflowContent.on.workflow_call.outputs.token_id).toBeDefined();
      expect(workflowContent.on.workflow_call.outputs.deployment_status).toBeDefined();
      
      // Should have deploy job
      expect(workflowContent.jobs.deploy).toBeDefined();
      expect(workflowContent.jobs.deploy.name).toBe('Deploy Cluster');
    });
  });

  describe('reusable-services-deployment workflow', () => {
    const workflowPath = path.join(workflowsDir, 'reusable-services-deployment.yml');

    it('SHOULD FAIL: reusable-services-deployment.yml must exist', () => {
      expect(fs.existsSync(workflowPath)).toBe(true);
    });

    it('SHOULD FAIL: reusable-services-deployment workflow must have correct structure', () => {
      if (!fs.existsSync(workflowPath)) {
        throw new Error('Workflow file does not exist - expected failure');
      }

      const workflowContent = yaml.load(fs.readFileSync(workflowPath, 'utf8'));
      
      expect(workflowContent.name).toBe('Reusable Services Deployment');
      expect(workflowContent.on.workflow_call).toBeDefined();
      
      // Required inputs
      expect(workflowContent.on.workflow_call.inputs.environment).toBeDefined();
      expect(workflowContent.on.workflow_call.inputs.service_type).toBeDefined();
      expect(workflowContent.on.workflow_call.inputs.version).toBeDefined();
      
      // Required outputs
      expect(workflowContent.on.workflow_call.outputs.service_status).toBeDefined();
      expect(workflowContent.on.workflow_call.outputs.service_urls).toBeDefined();
    });
  });

  describe('reusable-post-deployment-tests workflow', () => {
    const workflowPath = path.join(workflowsDir, 'reusable-post-deployment-tests.yml');

    it('SHOULD FAIL: reusable-post-deployment-tests.yml must exist', () => {
      expect(fs.existsSync(workflowPath)).toBe(true);
    });

    it('SHOULD FAIL: reusable-post-deployment-tests workflow must have correct structure', () => {
      if (!fs.existsSync(workflowPath)) {
        throw new Error('Workflow file does not exist - expected failure');
      }

      const workflowContent = yaml.load(fs.readFileSync(workflowPath, 'utf8'));
      
      expect(workflowContent.name).toBe('Reusable Post-Deployment Tests');
      expect(workflowContent.on.workflow_call).toBeDefined();
      
      // Required inputs
      expect(workflowContent.on.workflow_call.inputs.environment).toBeDefined();
      expect(workflowContent.on.workflow_call.inputs.test_suite).toBeDefined();
      expect(workflowContent.on.workflow_call.inputs.bridge_url).toBeDefined();
      expect(workflowContent.on.workflow_call.inputs.ml0_url).toBeDefined();
      
      // Required outputs
      expect(workflowContent.on.workflow_call.outputs.test_results).toBeDefined();
      expect(workflowContent.on.workflow_call.outputs.tests_passed).toBeDefined();
    });
  });
});

describe('Refactoring Impact Tests', () => {
  
  it('SHOULD FAIL: original workflows must be simplified after refactoring', () => {
    const originalWorkflows = [
      'release-scratch.yml',
      'deploy-dev-orchestrated.yml',
      'deploy-staging.yml',
      'deploy-production.yml'
    ];
    
    const workflowsDir = path.join(__dirname, '../.github/workflows');
    let totalLinesAfterRefactor = 0;
    
    for (const workflowFile of originalWorkflows) {
      const workflowPath = path.join(workflowsDir, workflowFile);
      if (fs.existsSync(workflowPath)) {
        const content = fs.readFileSync(workflowPath, 'utf8');
        const lineCount = content.split('\n').length;
        totalLinesAfterRefactor += lineCount;
        
        // Each workflow should be significantly smaller after refactoring
        expect(lineCount).toBeLessThan(200); // Much smaller than original
      }
    }
    
    // Total lines should be dramatically reduced from original 2,901
    expect(totalLinesAfterRefactor).toBeLessThan(800);
  });
  
  it('SHOULD FAIL: all original workflow patterns must be replaced with composite action calls', () => {
    const workflowsDir = path.join(__dirname, '../.github/workflows');
    const originalWorkflows = ['release-scratch.yml', 'deploy-dev-orchestrated.yml'];
    
    for (const workflowFile of originalWorkflows) {
      const workflowPath = path.join(workflowsDir, workflowFile);
      if (fs.existsSync(workflowPath)) {
        const content = fs.readFileSync(workflowPath, 'utf8');
        
        // Should not contain duplicate SSH setup patterns
        expect(content).not.toMatch(/mkdir -p ~\/\.ssh/);
        expect(content).not.toMatch(/chmod 600 ~\/\.ssh\/hetzner/);
        
        // Should not contain duplicate yq installation
        expect(content).not.toMatch(/snap install yq/);
        
        // Should not contain duplicate Java/sbt setup
        expect(content).not.toMatch(/setup-java@v4/);
        expect(content).not.toMatch(/sbt\/setup-sbt/);
        
        // Should use composite actions instead
        expect(content).toMatch(/\.\/.github\/actions\/setup-ssh/);
        expect(content).toMatch(/\.\/.github\/actions\/plan-deployment/);
      }
    }
  });
});

// Test runner setup
if (require.main === module) {
  const { execSync } = require('child_process');
  
  console.log('🧪 Running TDD tests for workflow refactoring...');
  console.log('These tests SHOULD FAIL until composite actions and reusable workflows are implemented.\n');
  
  try {
    execSync('npx jest --verbose tests/composite-actions.test.js', { stdio: 'inherit' });
    console.log('\n❌ Unexpected: Some tests passed! Implementation may already exist.');
    process.exit(1);
  } catch (error) {
    console.log('\n✅ Expected: All tests failed as expected (TDD approach)');
    console.log('📋 Next: Implement the composite actions and reusable workflows to make tests pass');
    process.exit(0);
  }
}