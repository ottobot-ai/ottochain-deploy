# TDD Workflow Refactoring Plan

## 🎯 Objective

Refactor 2,901 lines of duplicate GitHub Actions workflows into reusable components using Test-Driven Development (TDD).

## 📊 Current State (Before Refactoring)

| Workflow | Lines | Main Issues |
|----------|-------|-------------|
| release-scratch.yml | ~800 | SSH setup, JAR build, deployment logic duplication |
| release-scratch-layered.yml | ~450 | Similar patterns as above |
| deploy-dev-orchestrated.yml | ~400 | Service deployment duplication |
| deploy-staging.yml | ~150 | Environment setup duplication |
| deploy-production.yml | ~200 | Deployment planning duplication |
| deploy-layers.yml | ~150 | Layer management duplication |
| rollback.yml | ~300 | Container management duplication |
| deploy-development.yml | ~100 | Simple deployment patterns |
| **Total** | **2,900+** | **Massive code duplication** |

## 🧪 TDD Approach

### Step 1: Write Failing Tests (COMPLETED ✅)

Created comprehensive test suites that define the target architecture:

#### Test Files Created:
- **`tests/composite-actions.test.js`** - Tests for composite action structure
- **`tests/workflow-refactoring-requirements.test.js`** - Tests for overall refactoring requirements
- **`tests/composite-action-behavior.test.js`** - Tests for detailed implementation behavior
- **`.github/workflows/test-composite-actions.yml`** - Integration tests for composite actions
- **`.github/workflows/test-reusable-workflows.yml`** - Integration tests for reusable workflows

#### Test Coverage:
- ✅ 5 composite actions defined
- ✅ 4 reusable workflows defined  
- ✅ File structure requirements
- ✅ Duplication elimination requirements
- ✅ Performance improvement requirements
- ✅ Error handling requirements
- ✅ Documentation requirements

### Step 2: Implement Components (TODO)

Based on the failing tests, implement:

#### Composite Actions (`.github/actions/`)
1. **`setup-ssh/`** - SSH configuration for Hetzner nodes
2. **`plan-deployment/`** - Deployment planning with version comparison
3. **`setup-java-build/`** - Java, sbt, and repository setup
4. **`manage-containers/`** - Docker container start/stop/restart
5. **`setup-environment/`** - Environment configuration and .env file creation

#### Reusable Workflows (`.github/workflows/`)
1. **`reusable-jar-build.yml`** - JAR compilation workflow
2. **`reusable-cluster-deployment.yml`** - Full cluster deployment workflow
3. **`reusable-services-deployment.yml`** - Services deployment workflow
4. **`reusable-post-deployment-tests.yml`** - Post-deployment testing workflow

### Step 3: Refactor Main Workflows (TODO)

Update existing workflows to use the new components:

- `release-scratch.yml` → Use reusable workflows, reduce to ~150 lines
- `deploy-dev-orchestrated.yml` → Use composite actions, reduce to ~100 lines
- `deploy-staging.yml` → Use composite actions, reduce to ~80 lines
- Other workflows → Similar pattern

## 🎯 Success Metrics

The TDD tests define these success criteria:

### Code Reduction
- **Target**: 70%+ reduction in total lines (2,901 → <870)
- **Duplication**: 85%+ reduction in duplicated code patterns
- **Maintainability**: 80%+ improvement in maintainability score

### Performance Improvements
- **Build Time**: 25%+ faster through caching and parallelization
- **Cache Hit Rate**: 80%+ for reusable components
- **Error Recovery**: Faster debugging through centralized error handling

### Quality Improvements
- **Consistency**: Standardized interfaces across all deployments
- **Testing**: Comprehensive test coverage for all components
- **Documentation**: Complete documentation for all reusable components
- **Error Handling**: Proper error handling and reporting in all components

## 🚀 Implementation Strategy

### Phase 1: Foundation (Week 1)
1. Implement basic composite actions (`setup-ssh`, `plan-deployment`)
2. Create first reusable workflow (`reusable-jar-build`)
3. Validate with test suite

### Phase 2: Core Components (Week 1-2)
1. Implement remaining composite actions
2. Create cluster and services deployment workflows
3. Update 2-3 main workflows to use new components

### Phase 3: Complete Migration (Week 2)
1. Refactor all remaining main workflows
2. Add comprehensive documentation
3. Performance testing and optimization

### Phase 4: Validation (Week 2)
1. Run full test suite - all tests should pass ✅
2. Deploy to development environment for validation
3. Monitor performance improvements

## 📋 Test-Driven Implementation Guide

### Running the TDD Tests

```bash
# Install dependencies
npm install

# Run all TDD tests (should FAIL initially)
npm test

# Run specific test categories
npm run test:tdd
npx jest tests/composite-actions.test.js
npx jest tests/workflow-refactoring-requirements.test.js
npx jest tests/composite-action-behavior.test.js

# Run workflow integration tests (when components exist)
.github/workflows/test-composite-actions.yml
.github/workflows/test-reusable-workflows.yml
```

### Making Tests Pass

1. **Start with simplest composite action**: `setup-ssh`
   - Create `.github/actions/setup-ssh/action.yml`
   - Follow the exact structure defined in tests
   - Add error handling as specified

2. **Build incrementally**: Each component makes more tests pass
   - Tests are designed to guide implementation
   - Green tests = correctly implemented components

3. **Validate integration**: Use workflow tests to verify end-to-end behavior
   - Test workflows exercise the actual functionality
   - Ensures components work together correctly

## 🔍 Monitoring Progress

### Test Status Dashboard
- **Composite Actions**: 0/5 implemented (tests failing ❌)
- **Reusable Workflows**: 0/4 implemented (tests failing ❌)  
- **File Structure**: 0/9 directories created (tests failing ❌)
- **Documentation**: 0/5 README files (tests failing ❌)
- **Integration**: 0/2 test workflows passing (tests failing ❌)

### Implementation Checklist
- [ ] Create `.github/actions/` directory structure
- [ ] Implement `setup-ssh` composite action
- [ ] Implement `plan-deployment` composite action
- [ ] Implement `setup-java-build` composite action
- [ ] Implement `manage-containers` composite action
- [ ] Implement `setup-environment` composite action
- [ ] Create `reusable-jar-build.yml` workflow
- [ ] Create `reusable-cluster-deployment.yml` workflow
- [ ] Create `reusable-services-deployment.yml` workflow
- [ ] Create `reusable-post-deployment-tests.yml` workflow
- [ ] Refactor `release-scratch.yml`
- [ ] Refactor `deploy-dev-orchestrated.yml`
- [ ] Refactor remaining main workflows
- [ ] Add documentation for all components
- [ ] All TDD tests pass ✅

## 📈 Expected Results

When implementation is complete:

### Before Refactoring
```
❌ 2,901 lines of workflow code
❌ High duplication (SSH setup repeated 8+ times)
❌ Inconsistent error handling
❌ Difficult to maintain and debug
❌ Slow builds due to repeated setup
```

### After Refactoring
```
✅ <870 lines of workflow code (70% reduction)
✅ Zero duplication (DRY principle)
✅ Consistent error handling across all workflows
✅ Easy to maintain and extend
✅ 25%+ faster builds through reuse and caching
✅ Comprehensive test coverage
✅ Complete documentation
```

## 🛠️ Getting Started

1. **Review the failing tests** - they define exactly what to implement
2. **Start with `setup-ssh` composite action** - simplest component
3. **Follow TDD cycle**: Red → Green → Refactor
4. **Use test feedback** to guide implementation details
5. **Validate with integration tests** once components exist

The tests are your specification - make them pass! 🎯