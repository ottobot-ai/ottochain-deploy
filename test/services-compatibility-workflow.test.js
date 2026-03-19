/**
 * TDD Tests for Services Repository Compatibility Check Workflow
 * 
 * These tests define the expected behavior for the compatibility-check.yml workflow
 * that should be created in the ottochain-services repository.
 * 
 * This workflow receives dispatches from the deploy repository and runs
 * real integration tests with the specified metagraph version.
 */

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

describe('Services Repository Compatibility Check Workflow', () => {
  const servicesRepoPath = path.join(__dirname, '../../repos/ottochain-services');
  const workflowPath = path.join(servicesRepoPath, '.github/workflows/compatibility-check.yml');

  describe('Workflow Definition', () => {
    it('should exist as compatibility-check.yml in services repository', () => {
      // Assert: This workflow file should exist
      expect(() => {
        fs.accessSync(workflowPath, fs.constants.F_OK);
      }).not.toThrow();
    });

    it('should accept workflow_dispatch trigger with required inputs', () => {
      // Arrange & Act
      const workflow = yaml.load(fs.readFileSync(workflowPath, 'utf8'));

      // Assert: Should have proper dispatch inputs
      expect(workflow.on.workflow_dispatch.inputs).toEqual({
        metagraph_version: {
          description: 'OttoChain metagraph version to test compatibility against',
          required: true,
          type: 'string'
        },
        deploy_pr_number: {
          description: 'Deploy repository PR number requesting this compatibility test',
          required: true,
          type: 'number'
        },
        services_ref: {
          description: 'Services branch/ref to test (defaults to main)',
          required: false,
          type: 'string',
          default: 'main'
        },
        matrix_test: {
          description: 'Run matrix test including previous metagraph version',
          required: false,
          type: 'boolean',
          default: false
        }
      });
    });

    it('should have repository_dispatch trigger for cross-repo automation', () => {
      // Act
      const workflow = yaml.load(fs.readFileSync(workflowPath, 'utf8'));

      // Assert: Should accept external dispatches
      expect(workflow.on).toHaveProperty('repository_dispatch');
      expect(workflow.on.repository_dispatch.types).toContain('compatibility-check');
    });
  });

  describe('Job Configuration', () => {
    it('should define compatibility-test job with proper setup', () => {
      // Act
      const workflow = yaml.load(fs.readFileSync(workflowPath, 'utf8'));

      // Assert: Should have main compatibility test job
      expect(workflow.jobs).toHaveProperty('compatibility-test');
      expect(workflow.jobs['compatibility-test']).toMatchObject({
        'runs-on': 'ubuntu-latest',
        'timeout-minutes': 45,
        strategy: {
          matrix: {
            include: expect.arrayContaining([
              {
                metagraph_version: '${{ github.event.inputs.metagraph_version }}',
                services_ref: '${{ github.event.inputs.services_ref }}'
              }
            ])
          }
        }
      });
    });

    it('should include PostgreSQL service for integration tests', () => {
      // Act
      const workflow = yaml.load(fs.readFileSync(workflowPath, 'utf8'));

      // Assert: Should set up required services
      expect(workflow.jobs['compatibility-test'].services.postgres).toMatchObject({
        image: 'postgres:16-alpine',
        env: {
          POSTGRES_USER: 'ottochain',
          POSTGRES_PASSWORD: 'ottochain',
          POSTGRES_DB: 'ottochain'
        },
        ports: ['5432:5432'],
        options: expect.stringContaining('health-cmd')
      });
    });
  });

  describe('Status Check Integration Steps', () => {
    it('should create pending status check on deploy PR at job start', () => {
      // Act
      const workflow = yaml.load(fs.readFileSync(workflowPath, 'utf8'));
      
      // Assert: Should have step to create pending status
      const steps = workflow.jobs['compatibility-test'].steps;
      const statusStep = steps.find(step => step.name === 'Create pending status check');
      
      expect(statusStep).toEqual({
        name: 'Create pending status check',
        uses: 'actions/github-script@v7',
        with: {
          'github-token': '${{ secrets.DEPLOY_REPO_TOKEN }}',
          script: expect.stringContaining('repos/ottobot-ai/ottochain-deploy/statuses')
        }
      });
    });

    it('should update status check to success on test success', () => {
      // Act
      const workflow = yaml.load(fs.readFileSync(workflowPath, 'utf8'));
      
      // Assert: Should have step to update status on success
      const steps = workflow.jobs['compatibility-test'].steps;
      const successStep = steps.find(step => step.name === 'Update status check - success');
      
      expect(successStep).toEqual({
        name: 'Update status check - success',
        if: 'success()',
        uses: 'actions/github-script@v7',
        with: {
          'github-token': '${{ secrets.DEPLOY_REPO_TOKEN }}',
          script: expect.stringContaining('state: "success"')
        }
      });
    });

    it('should update status check to failure on test failure', () => {
      // Act
      const workflow = yaml.load(fs.readFileSync(workflowPath, 'utf8'));
      
      // Assert: Should have step to update status on failure
      const steps = workflow.jobs['compatibility-test'].steps;
      const failureStep = steps.find(step => step.name === 'Update status check - failure');
      
      expect(failureStep).toEqual({
        name: 'Update status check - failure',
        if: 'failure()',
        uses: 'actions/github-script@v7',
        with: {
          'github-token': '${{ secrets.DEPLOY_REPO_TOKEN }}',
          script: expect.stringContaining('state: "failure"')
        }
      });
    });
  });

  describe('Cluster Setup Steps', () => {
    it('should download and setup specified metagraph version', () => {
      // Act
      const workflow = yaml.load(fs.readFileSync(workflowPath, 'utf8'));
      
      // Assert: Should have step to download metagraph
      const steps = workflow.jobs['compatibility-test'].steps;
      const downloadStep = steps.find(step => step.name === 'Download metagraph JAR');
      
      expect(downloadStep).toMatchObject({
        name: 'Download metagraph JAR',
        run: expect.stringContaining('curl -L -o metagraph.jar')
      });
    });

    it('should spin up local tessellation cluster with specified version', () => {
      // Act
      const workflow = yaml.load(fs.readFileSync(workflowPath, 'utf8'));
      
      // Assert: Should have step to start cluster
      const steps = workflow.jobs['compatibility-test'].steps;
      const clusterStep = steps.find(step => step.name === 'Start tessellation cluster');
      
      expect(clusterStep).toMatchObject({
        name: 'Start tessellation cluster',
        run: expect.stringContaining('docker-compose -f docker-compose.ci.yaml up -d')
      });
    });

    it('should wait for cluster health before proceeding', () => {
      // Act
      const workflow = yaml.load(fs.readFileSync(workflowPath, 'utf8'));
      
      // Assert: Should have health check step
      const steps = workflow.jobs['compatibility-test'].steps;
      const healthStep = steps.find(step => step.name === 'Wait for cluster health');
      
      expect(healthStep).toMatchObject({
        name: 'Wait for cluster health',
        run: expect.stringContaining('timeout 600'),
        'timeout-minutes': 10
      });
    });
  });

  describe('Integration Test Steps', () => {
    it('should run database migrations and seeding', () => {
      // Act
      const workflow = yaml.load(fs.readFileSync(workflowPath, 'utf8'));
      
      // Assert: Should have database setup step
      const steps = workflow.jobs['compatibility-test'].steps;
      const dbStep = steps.find(step => step.name === 'Setup database');
      
      expect(dbStep).toMatchObject({
        name: 'Setup database',
        run: expect.stringContaining('pnpm run db:migrate')
      });
    });

    it('should run comprehensive integration test suite', () => {
      // Act
      const workflow = yaml.load(fs.readFileSync(workflowPath, 'utf8'));
      
      // Assert: Should run full integration tests
      const steps = workflow.jobs['compatibility-test'].steps;
      const testStep = steps.find(step => step.name === 'Run compatibility integration tests');
      
      expect(testStep).toMatchObject({
        name: 'Run compatibility integration tests',
        run: 'pnpm run test:integration:compatibility',
        env: {
          NODE_ENV: 'test',
          METAGRAPH_VERSION: '${{ matrix.metagraph_version }}',
          SERVICES_REF: '${{ matrix.services_ref }}'
        }
      });
    });

    it('should test key integration points between services and metagraph', () => {
      // This test validates that the integration test script covers essential compatibility areas
      const integrationTestScript = path.join(servicesRepoPath, 'scripts/test-compatibility.js');
      
      // Act & Assert: This script should exist and test core integration points
      expect(() => {
        const script = fs.readFileSync(integrationTestScript, 'utf8');
        expect(script).toContain('metagraph health check');
        expect(script).toContain('data indexing pipeline');
        expect(script).toContain('websocket subscriptions');
        expect(script).toContain('state machine execution');
        expect(script).toContain('API endpoint compatibility');
      }).not.toThrow();
    });
  });

  describe('Cleanup and Artifacts', () => {
    it('should cleanup cluster resources after test completion', () => {
      // Act
      const workflow = yaml.load(fs.readFileSync(workflowPath, 'utf8'));
      
      // Assert: Should have cleanup step that always runs
      const steps = workflow.jobs['compatibility-test'].steps;
      const cleanupStep = steps.find(step => step.name === 'Cleanup cluster');
      
      expect(cleanupStep).toMatchObject({
        name: 'Cleanup cluster',
        if: 'always()',
        run: expect.stringContaining('docker-compose -f docker-compose.ci.yaml down -v')
      });
    });

    it('should upload test logs and artifacts on failure', () => {
      // Act
      const workflow = yaml.load(fs.readFileSync(workflowPath, 'utf8'));
      
      // Assert: Should upload artifacts for debugging
      const steps = workflow.jobs['compatibility-test'].steps;
      const artifactStep = steps.find(step => step.name === 'Upload test artifacts');
      
      expect(artifactStep).toMatchObject({
        name: 'Upload test artifacts',
        if: 'failure()',
        uses: 'actions/upload-artifact@v4',
        with: {
          name: 'compatibility-test-logs-${{ matrix.metagraph_version }}',
          path: expect.stringContaining('logs/')
        }
      });
    });
  });

  describe('Matrix Testing Support', () => {
    it('should support matrix testing when matrix_test input is true', () => {
      // Act
      const workflow = yaml.load(fs.readFileSync(workflowPath, 'utf8'));
      
      // Assert: Should have conditional matrix expansion
      const strategy = workflow.jobs['compatibility-test'].strategy;
      expect(strategy.matrix).toEqual({
        include: [
          {
            metagraph_version: '${{ github.event.inputs.metagraph_version }}',
            services_ref: '${{ github.event.inputs.services_ref }}'
          },
          {
            metagraph_version: '${{ github.event.inputs.previous_metagraph_version }}',
            services_ref: '${{ github.event.inputs.services_ref }}',
            if: '${{ github.event.inputs.matrix_test == "true" }}'
          }
        ]
      });
    });

    it('should generate comparison report for matrix results', () => {
      // Act: This step should exist for matrix test scenarios
      const workflow = yaml.load(fs.readFileSync(workflowPath, 'utf8'));
      
      // Assert: Should have step to compare matrix results
      const steps = workflow.jobs['compatibility-test'].steps;
      const reportStep = steps.find(step => step.name === 'Generate matrix comparison report');
      
      expect(reportStep).toEqual({
        name: 'Generate matrix comparison report',
        if: '${{ github.event.inputs.matrix_test == "true" }}',
        run: expect.stringContaining('node scripts/compare-matrix-results.js')
      });
    });
  });
});

// Additional test for the updated validate-versions.yml workflow in deploy repo
describe('Deploy Repository validate-versions.yml Integration', () => {
  const deployWorkflowPath = path.join(__dirname, '../.github/workflows/validate-versions.yml');

  it('should detect metagraph version changes and trigger compatibility check', () => {
    // Act
    const workflow = yaml.load(fs.readFileSync(deployWorkflowPath, 'utf8'));
    
    // Assert: Should have step to trigger compatibility check
    const steps = workflow.jobs.validate.steps;
    const triggerStep = steps.find(step => step.name === 'Trigger compatibility check');
    
    expect(triggerStep).toEqual({
      name: 'Trigger compatibility check',
      if: '${{ env.METAGRAPH_VERSION_CHANGED == "true" }}',
      uses: 'actions/github-script@v7',
      with: {
        'github-token': '${{ secrets.SERVICES_REPO_TOKEN }}',
        script: expect.stringContaining('repository_dispatch')
      }
    });
  });

  it('should extract previous and new metagraph versions for comparison', () => {
    // Act
    const workflow = yaml.load(fs.readFileSync(deployWorkflowPath, 'utf8'));
    
    // Assert: Should have step to detect version changes
    const steps = workflow.jobs.validate.steps;
    const versionStep = steps.find(step => step.name === 'Detect metagraph version changes');
    
    expect(versionStep).toMatchObject({
      name: 'Detect metagraph version changes',
      run: expect.stringContaining('git show HEAD^:versions.yaml')
    });
  });
});