# CI/CD Documentation

This document covers the continuous integration and deployment pipeline for usbipd-mac, including CI configuration, testing strategies, branch protection, and troubleshooting procedures.

## Overview

This project uses GitHub Actions for continuous integration to ensure code quality and prevent regressions. The CI pipeline automatically runs on every pull request and push to the main branch, providing fast feedback to developers.

## CI Pipeline Overview

The CI pipeline consists of four parallel jobs that validate different aspects of the codebase:

### 1. Code Quality (SwiftLint)
- **Purpose**: Validates Swift code style and consistency
- **Tool**: SwiftLint with project-specific configuration (`.swiftlint.yml`)
- **Execution**: Runs in strict mode where warnings are treated as errors
- **Caching**: SwiftLint installation is cached for faster execution

### 2. Build Validation
- **Purpose**: Ensures the project compiles successfully
- **Tool**: Swift Package Manager with latest Swift version
- **Environment**: Latest macOS runner with verbose build output
- **Caching**: Swift packages and build artifacts are cached

### 3. Unit Tests
- **Purpose**: Validates functionality through automated unit tests
- **Coverage**: USBIPDCoreTests and USBIPDCLITests suites
- **Execution**: Parallel test execution with verbose output
- **Environment**: Latest Swift and macOS versions

### 4. Integration Tests (QEMU)
- **Purpose**: End-to-end validation with QEMU test server
- **Components**: QEMU test server build and validation script
- **Coverage**: Network communication and protocol flow testing
- **Dependencies**: Builds QEMUTestServer product and runs validation script

## Running Checks Locally

Before submitting a pull request, you can run the same checks locally to catch issues early:

### Code Quality Check
```bash
# Install SwiftLint (if not already installed)
brew install swiftlint

# Run SwiftLint with the same strict settings as CI
swiftlint lint --strict

# Auto-fix some violations (optional)
swiftlint --fix
```

### Build Validation
```bash
# Clean build to match CI environment
swift package clean

# Resolve dependencies
swift package resolve

# Build project with verbose output
swift build --verbose
```

### Unit Tests
```bash
# Run all unit tests with parallel execution
swift test --parallel --verbose

# Run specific test suite
swift test --filter USBIPDCoreTests
swift test --filter USBIPDCLITests
```

### Integration Tests
```bash
# Build QEMU test server
swift build --product QEMUTestServer

# Run QEMU validation script
./Scripts/qemu-test-validation.sh

# Run integration tests specifically
swift test --filter IntegrationTests --verbose
```

### Complete Local Validation
```bash
# Run all checks in sequence (mimics CI pipeline)
echo "Running SwiftLint..."
swiftlint lint --strict

echo "Building project..."
swift build --verbose

echo "Running unit tests..."
swift test --parallel --verbose

echo "Running integration tests..."
./Scripts/qemu-test-validation.sh
swift test --filter IntegrationTests --verbose

echo "All checks completed successfully!"
```

## Performance Optimization

The CI pipeline is optimized for fast feedback:

- **Parallel Execution**: All four jobs run simultaneously
- **Dependency Caching**: Swift packages and SwiftLint are cached between runs
- **Incremental Builds**: Build artifacts are cached when possible
- **Target Execution Time**: Complete pipeline typically runs under 10 minutes

## Branch Protection

The main branch is protected with required status checks and approval requirements. Pull requests cannot be merged until:

### Required Status Checks
- Code Quality (SwiftLint) ✅
- Build Validation ✅  
- Unit Tests ✅
- Integration Tests (QEMU) ✅

### Approval Requirements
- At least 1 maintainer review and approval ✅
- Branch must be up to date with main ✅
- Stale reviews dismissed on new commits ✅
- Administrators cannot bypass without approval ✅

### Setup and Validation
```bash
# Using the provided setup script
./.github/scripts/setup-branch-protection.sh
```

This ensures that even if technical checks could be bypassed, maintainer approval acts as a safeguard to maintain code quality and project stability.

### Maintainer Approval Process

When CI checks fail or need to be bypassed:

1. **Normal Process**: Fix the failing checks and push new commits
2. **Emergency Bypass**: 
   - Requires explicit approval from repository maintainers
   - Maintainer must review the specific reason for bypass
   - Approval must be documented in PR comments
   - Follow-up issue should be created to address the underlying problem

### Configuration Details
- Administrators cannot bypass protection rules without approval
- All status checks must pass before merging
- At least 1 maintainer approval is required for all PRs
- Stale reviews are dismissed when new commits are pushed

Branch protection rules should be configured through GitHub's repository settings.

## Troubleshooting CI Issues

If CI checks fail, here are common solutions and next steps:

### Quick Diagnosis Steps

1. **Identify the failing job**: Check which specific job failed (lint, build, test, integration-test)
2. **Review error summary**: Each job provides a summary with common causes
3. **Run locally first**: Always reproduce the issue locally before investigating CI-specific problems
4. **Check recent changes**: Consider if recent updates might be the cause

### Common Issues and Solutions

#### SwiftLint Failures
```bash
# Check violations locally
swiftlint lint --strict

# Auto-fix violations where possible
swiftlint --fix

# Verify configuration
python -c "import yaml; yaml.safe_load(open('.swiftlint.yml'))"
```

#### Build Failures
```bash
# Clean build to match CI environment
swift package clean
swift package resolve
swift build --verbose

# Check for dependency conflicts
swift package show-dependencies
```

#### Test Failures
```bash
# Run tests with detailed output
swift test --verbose --parallel

# Run specific test suite
swift test --filter USBIPDCoreTests
swift test --filter USBIPDCLITests
```

#### Integration Test Failures
```bash
# Build and test QEMU server
swift build --product QEMUTestServer
./Scripts/qemu-test-validation.sh

# Run integration tests specifically
swift test --filter IntegrationTests --verbose
```

### Updating Swift and macOS Versions

When new Swift or macOS versions become available:

#### Swift Version Updates
1. Update `Package.swift` tools version: `// swift-tools-version:5.9`
2. Test locally: `swift build && swift test`
3. Update CI if using specific version (workflow uses `latest` by default)
4. Handle deprecated APIs and breaking changes

#### macOS Version Updates
1. CI automatically uses `macos-latest` (currently macOS 13+)
2. Update minimum deployment target if needed: `.macOS(.v13)`
3. Add availability checks for new APIs:
   ```swift
   if #available(macOS 14.0, *) {
       // Use new API
   } else {
       // Fallback implementation
   }
   ```

### Performance Issues

If CI execution exceeds 10 minutes:
- Check dependency caching effectiveness
- Profile slow tests: `swift test --verbose 2>&1 | grep "Test Case.*passed"`
- Optimize build configuration for performance testing
- Consider parallel execution improvements

### For Comprehensive Troubleshooting

For comprehensive troubleshooting, refer to the following procedures:
- Detailed diagnosis procedures for each job type
- Step-by-step solutions for common issues
- Swift and macOS version update procedures
- Cache optimization and debugging
- Branch protection troubleshooting
- Emergency procedures for critical issues

### Getting Help

If these solutions don't resolve your issue:
1. Follow the comprehensive troubleshooting procedures documented above
2. Review CI job logs for detailed error messages
3. Reproduce the issue locally using the same commands
4. Check [GitHub Actions status](https://www.githubstatus.com/) for platform issues
5. Consult project maintainers for project-specific guidance

## CI Pipeline Test Scenarios

This section describes the test scenarios created to verify that the GitHub Actions CI pipeline properly catches and reports different types of failures.

### Test Branches Created

#### 1. SwiftLint Violations (`test/swiftlint-violations`)

**Purpose**: Verify that the CI pipeline catches code style violations and blocks merges.

**Violations Introduced**:
- **Line Length Violation**: Added a comment that exceeds the maximum line length limit
- **TODO/FIXME Violations**: Added TODO and FIXME comments that should trigger warnings
- **Force Unwrapping Violation**: Added force unwrapping (`!`) which should be flagged
- **Trailing Whitespace Violation**: Added lines with trailing whitespace

**Expected CI Behavior**:
- ✅ SwiftLint job should **FAIL**
- ✅ Build and test jobs should be **SKIPPED** or **CANCELLED** (depending on workflow dependencies)
- ✅ PR should be **BLOCKED** from merging
- ✅ Clear error messages should be displayed in the CI output

**File Modified**: `Sources/Common/Logger.swift`

#### 2. Build Errors (`test/build-errors`)

**Purpose**: Verify that the CI pipeline catches compilation errors and blocks merges.

**Errors Introduced**:
- **Missing Closing Brace**: Enum definition with missing closing brace
- **Unknown Type Reference**: Reference to `UnknownType` that doesn't exist
- **Invalid Swift Syntax**: Malformed syntax that won't compile
- **Invalid Variable Declaration**: Malformed `let` statement

**Expected CI Behavior**:
- ✅ SwiftLint job should **PASS** (no style violations)
- ✅ Build job should **FAIL** with compilation errors
- ✅ Test jobs should be **SKIPPED** (can't test if build fails)
- ✅ PR should be **BLOCKED** from merging
- ✅ Detailed compilation error messages should be displayed

**File Modified**: `Sources/Common/Errors.swift`

#### 3. Test Failures (`test/test-failures`)

**Purpose**: Verify that the CI pipeline catches unit test failures and blocks merges.

**Test Failures Introduced**:
- **Modified Assertions**: Changed correct assertions to incorrect ones
- **Wrong Expected Values**: Changed expected values in tests to cause failures
- **Intentional Failure**: Added a test that always fails with `XCTFail()`
- **Logic Errors**: Modified test logic to expect wrong behavior

**Expected CI Behavior**:
- ✅ SwiftLint job should **PASS** (no style violations)
- ✅ Build job should **PASS** (code compiles successfully)
- ✅ Unit Test job should **FAIL** with test failures
- ✅ Integration Test job should be **SKIPPED** or **CANCELLED**
- ✅ PR should be **BLOCKED** from merging
- ✅ Detailed test failure messages should be displayed

**File Modified**: `Tests/USBIPDCoreTests/LoggerTests.swift`

### Verification Steps

#### 1. Merge CI Workflow to Main

**Important**: The CI workflow is currently in the `feature/github-actions-ci` branch and must be merged to `main` first for the test scenarios to work properly.

```bash
# Merge the CI workflow to main
git checkout main
git merge feature/github-actions-ci
git push origin main
```

#### 2. Create Pull Requests

For each test branch, create a pull request to `main`:

1. **SwiftLint Violations PR**:
   ```bash
   # Create PR from test/swiftlint-violations to main
   # Expected: PR shows failing checks, merge is blocked
   ```

2. **Build Errors PR**:
   ```bash
   # Create PR from test/build-errors to main
   # Expected: PR shows failing checks, merge is blocked
   ```

3. **Test Failures PR**:
   ```bash
   # Create PR from test/test-failures to main
   # Expected: PR shows failing checks, merge is blocked
   ```

#### 3. Verify Branch Protection Rules

Ensure that branch protection rules are properly configured:

- ✅ Require status checks to pass before merging
- ✅ Require branches to be up to date before merging
- ✅ Required status checks include:
  - `Code Quality (SwiftLint)`
  - `Build Validation`
  - `Unit Tests`
  - `Integration Tests (QEMU)`

#### 4. Verify Error Reporting

Check that the CI pipeline provides clear, actionable error messages:

1. **SwiftLint Errors**: Should show specific rule violations with file locations
2. **Build Errors**: Should show compilation errors with file and line numbers
3. **Test Failures**: Should show which tests failed and why

### Expected Outcomes

#### ✅ Success Criteria

1. **Proper Failure Detection**: Each type of failure is caught by the appropriate CI job
2. **Clear Error Messages**: Failures include detailed, actionable error information
3. **Merge Blocking**: PRs with failures cannot be merged due to branch protection
4. **Status Reporting**: GitHub shows clear status indicators for each check
5. **Workflow Dependencies**: Jobs that depend on failed jobs are properly skipped

#### ❌ Failure Indicators

If any of these occur, the CI pipeline needs adjustment:

1. **False Positives**: CI fails when code is actually correct
2. **False Negatives**: CI passes when there are actual problems
3. **Unclear Messages**: Error messages don't help developers fix issues
4. **Merge Allowed**: PRs can be merged despite failing checks
5. **Resource Waste**: Jobs continue running after dependencies fail

### Cleanup

After verification is complete, clean up the test branches:

```bash
# Delete local branches
git branch -D test/swiftlint-violations
git branch -D test/build-errors
git branch -D test/test-failures

# Delete remote branches
git push origin --delete test/swiftlint-violations
git push origin --delete test/build-errors
git push origin --delete test/test-failures
```

### Requirements Validation

This testing validates the following requirements:

- **Requirement 1.2**: Code quality validation through SwiftLint integration
- **Requirement 2.3**: Build validation to catch compilation errors
- **Requirement 3.2**: Comprehensive unit test execution
- **Requirement 6.1**: Proper error reporting and merge blocking

### Notes

- These test branches contain intentionally broken code and should **never** be merged to `main`
- The test scenarios are designed to be obvious failures that are easy to identify and fix
- Each test branch focuses on a single type of failure to isolate testing
- The CI pipeline should provide clear guidance on how to fix each type of failure