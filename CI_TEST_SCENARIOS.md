# CI Pipeline Test Scenarios

This document describes the test scenarios created to verify that the GitHub Actions CI pipeline properly catches and reports different types of failures.

## Test Branches Created

### 1. SwiftLint Violations (`test/swiftlint-violations`)

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

### 2. Build Errors (`test/build-errors`)

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

### 3. Test Failures (`test/test-failures`)

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

## Verification Steps

### 1. Check GitHub Actions Workflow Runs

1. Navigate to the repository's **Actions** tab
2. Look for workflow runs triggered by the test branches
3. Verify that each run shows the expected failure pattern:
   - `test/swiftlint-violations`: SwiftLint job fails
   - `test/build-errors`: Build job fails
   - `test/test-failures`: Test job fails

### 2. Create Pull Requests

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

### 3. Verify Branch Protection Rules

Ensure that branch protection rules are properly configured:

- ✅ Require status checks to pass before merging
- ✅ Require branches to be up to date before merging
- ✅ Required status checks include:
  - `Code Quality (SwiftLint)`
  - `Build Validation`
  - `Unit Tests`
  - `Integration Tests (QEMU)`

### 4. Verify Error Reporting

Check that the CI pipeline provides clear, actionable error messages:

1. **SwiftLint Errors**: Should show specific rule violations with file locations
2. **Build Errors**: Should show compilation errors with file and line numbers
3. **Test Failures**: Should show which tests failed and why

## Expected Outcomes

### ✅ Success Criteria

1. **Proper Failure Detection**: Each type of failure is caught by the appropriate CI job
2. **Clear Error Messages**: Failures include detailed, actionable error information
3. **Merge Blocking**: PRs with failures cannot be merged due to branch protection
4. **Status Reporting**: GitHub shows clear status indicators for each check
5. **Workflow Dependencies**: Jobs that depend on failed jobs are properly skipped

### ❌ Failure Indicators

If any of these occur, the CI pipeline needs adjustment:

1. **False Positives**: CI fails when code is actually correct
2. **False Negatives**: CI passes when there are actual problems
3. **Unclear Messages**: Error messages don't help developers fix issues
4. **Merge Allowed**: PRs can be merged despite failing checks
5. **Resource Waste**: Jobs continue running after dependencies fail

## Cleanup

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

## Requirements Validation

This testing validates the following requirements:

- **Requirement 1.2**: Code quality validation through SwiftLint integration
- **Requirement 2.3**: Build validation to catch compilation errors
- **Requirement 3.2**: Comprehensive unit test execution
- **Requirement 6.1**: Proper error reporting and merge blocking

## Notes

- These test branches contain intentionally broken code and should **never** be merged to `main`
- The test scenarios are designed to be obvious failures that are easy to identify and fix
- Each test branch focuses on a single type of failure to isolate testing
- The CI pipeline should provide clear guidance on how to fix each type of failure