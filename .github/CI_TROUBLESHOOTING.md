# CI Troubleshooting Guide

This comprehensive guide provides detailed solutions for common CI issues and procedures for maintaining the GitHub Actions workflow.

## Table of Contents

1. [Quick Diagnosis](#quick-diagnosis)
2. [SwiftLint Issues](#swiftlint-issues)
3. [Build Issues](#build-issues)
4. [Test Issues](#test-issues)
5. [Integration Test Issues](#integration-test-issues)
6. [Performance Issues](#performance-issues)
7. [Swift and macOS Version Updates](#swift-and-macos-version-updates)
8. [Cache Issues](#cache-issues)
9. [Branch Protection Issues](#branch-protection-issues)
10. [Emergency Procedures](#emergency-procedures)

## Quick Diagnosis

### Step 1: Identify the Problem

1. **Check the CI status**: Look at which specific job failed
2. **Review the error summary**: Each job provides a summary with common causes
3. **Check the timing**: Note if the failure is consistent or intermittent

### Step 2: Reproduce Locally

Always reproduce the issue locally before investigating CI-specific problems:

```bash
# Run the complete local validation sequence
echo "🔍 Running SwiftLint..."
swiftlint lint --strict --reporter xcode

echo "🔨 Building project..."
swift package clean && swift package resolve && swift build --verbose

echo "🧪 Running unit tests..."
swift test --verbose --parallel

echo "🔗 Running integration tests..."
chmod +x Scripts/run-qemu-tests.sh
swift build --product QEMUTestServer
./Scripts/run-qemu-tests.sh
swift test --filter IntegrationTests --verbose
```

### Step 3: Check Environment Differences

Compare your local environment with CI:

```bash
# Check versions (should match CI)
swift --version
sw_vers -productName && sw_vers -productVersion
swiftlint version
which swiftlint
```

## SwiftLint Issues

### Common SwiftLint Violations

#### Line Length Violations
```
error: Line Length Violation: Line should be 120 characters or less: currently 145 characters (line_length)
```

**Solutions:**
```swift
// ❌ Too long
let veryLongVariableName = someObject.someMethod().anotherMethod().yetAnotherMethod().finalMethod()

// ✅ Break into multiple lines
let veryLongVariableName = someObject
    .someMethod()
    .anotherMethod()
    .yetAnotherMethod()
    .finalMethod()

// ✅ Use intermediate variables
let intermediateResult = someObject.someMethod().anotherMethod()
let veryLongVariableName = intermediateResult.yetAnotherMethod().finalMethod()
```

#### Force Cast/Unwrapping Violations
```
error: Force Cast Violation: Force casts should be avoided (force_cast)
error: Force Unwrapping Violation: Force unwrapping should be avoided (force_unwrapping)
```

**Solutions:**
```swift
// ❌ Force casting and unwrapping
let result = someValue as! String
let unwrapped = optionalValue!

// ✅ Safe casting and unwrapping
guard let result = someValue as? String else {
    // Handle casting failure
    return
}

if let unwrapped = optionalValue {
    // Use unwrapped value
} else {
    // Handle nil case
}

// ✅ Nil coalescing for defaults
let value = optionalValue ?? defaultValue
```

#### Trailing Whitespace
```
warning: Trailing Whitespace: Lines should not have trailing whitespace (trailing_whitespace)
```

**Solutions:**
```bash
# Auto-fix trailing whitespace
swiftlint --fix

# Configure your editor to show/remove trailing whitespace
# Xcode: Preferences > Text Editing > While editing > Including whitespace-only lines
```

### SwiftLint Configuration Issues

#### Invalid YAML Configuration
```
error: Could not read configuration file at '.swiftlint.yml': The operation couldn't be completed.
```

**Diagnosis:**
```bash
# Validate YAML syntax
python -c "import yaml; yaml.safe_load(open('.swiftlint.yml'))"

# Check for common YAML issues
cat .swiftlint.yml | grep -E "^\s*-\s*$|^\s*:\s*$"
```

**Common YAML Issues:**
- Missing spaces after colons: `key:value` → `key: value`
- Incorrect indentation (use spaces, not tabs)
- Missing quotes around special characters
- Trailing commas in lists

#### SwiftLint Installation Issues
```
error: SwiftLint not found in PATH
```

**Solutions:**
```bash
# Install SwiftLint
brew install swiftlint

# Verify installation
which swiftlint
swiftlint version

# If Homebrew is not available, use alternative installation
curl -L https://github.com/realm/SwiftLint/releases/latest/download/portable_swiftlint.zip -o swiftlint.zip
unzip swiftlint.zip
sudo mv swiftlint /usr/local/bin/
```

## Build Issues

### Dependency Resolution Failures

#### Network Connectivity Issues
```
error: failed to resolve dependencies: unable to resolve package at 'https://github.com/...'
```

**Solutions:**
```bash
# Clear package cache
rm -rf .build
swift package clean

# Reset package state
swift package reset

# Resolve with verbose output
swift package resolve --verbose

# Check network connectivity
curl -I https://github.com

# Use SSH instead of HTTPS if authentication issues
# Update Package.swift to use SSH URLs for private repos
```

#### Version Conflicts
```
error: package 'PackageName' is required using two different revision-based requirements
```

**Solutions:**
```bash
# Show dependency tree
swift package show-dependencies

# Update Package.swift to use compatible versions
# Remove version conflicts by specifying exact versions or ranges

# Example fix in Package.swift:
.package(url: "https://github.com/example/package", from: "1.0.0")
// Instead of mixing exact and range requirements
```

### Compilation Errors

#### Missing Imports
```
error: no such module 'ModuleName'
```

**Solutions:**
```swift
// Check Package.swift dependencies
.target(
    name: "YourTarget",
    dependencies: [
        "MissingModule", // Add missing dependency
    ]
)

// Verify import statement
import Foundation
import MissingModule // Ensure correct module name
```

#### Symbol Not Found
```
error: cannot find 'symbolName' in scope
```

**Solutions:**
```swift
// Check if symbol is properly imported
import ModuleContainingSymbol

// Verify symbol visibility (public/internal)
public func symbolName() { } // Ensure it's public if used across modules

// Check for typos in symbol names
// Use Xcode's autocomplete to verify correct spelling
```

### Swift Version Compatibility

#### Deprecated API Usage
```
warning: 'oldAPI' is deprecated in Swift 5.9: use 'newAPI' instead
```

**Solutions:**
```swift
// Use availability checks for gradual migration
if #available(macOS 14.0, *) {
    // Use new API
    newAPI()
} else {
    // Use old API for backward compatibility
    oldAPI()
}

// Or update to use new API directly if minimum version allows
newAPI() // When minimum deployment target supports it
```

## Test Issues

### Test Discovery Problems

#### No Tests Found
```
error: no tests found
```

**Solutions:**
```bash
# Verify test target configuration in Package.swift
.testTarget(
    name: "YourTests",
    dependencies: ["YourModule"]
)

# Check test file naming (must end with 'Tests')
# Example: DeviceManagerTests.swift

# Verify test class inheritance
import XCTest
@testable import YourModule

final class YourTests: XCTestCase {
    func testExample() {
        // Test implementation
    }
}
```

### Test Execution Failures

#### Timeout Issues
```
error: Test Case 'TestClass.testMethod' exceeded timeout of 60.0 seconds
```

**Solutions:**
```swift
// Add explicit timeouts for async operations
func testAsyncOperation() async throws {
    let expectation = XCTestExpectation(description: "Async operation")
    
    // Set appropriate timeout
    await fulfillment(of: [expectation], timeout: 30.0)
}

// Use XCTAssertNoThrow for operations that might hang
XCTAssertNoThrow(try potentiallyHangingOperation())
```

#### Memory Issues
```
error: Test crashed with signal SIGKILL
```

**Solutions:**
```swift
// Check for memory leaks in test setup/teardown
override func tearDown() {
    // Clean up resources
    testObject = nil
    super.tearDown()
}

// Use weak references to avoid retain cycles
weak var weakDelegate = delegate
XCTAssertNil(weakDelegate) // Verify cleanup
```

### Flaky Tests

#### Race Conditions
```
error: Test sometimes passes, sometimes fails
```

**Solutions:**
```swift
// Use proper synchronization for concurrent tests
func testConcurrentOperation() async {
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<10 {
            group.addTask {
                await self.performOperation(i)
            }
        }
    }
}

// Use XCTestExpectation for async operations
let expectation = XCTestExpectation(description: "Operation completes")
asyncOperation { result in
    XCTAssertNotNil(result)
    expectation.fulfill()
}
await fulfillment(of: [expectation], timeout: 5.0)
```

## Integration Test Issues

### QEMU Test Server Issues

#### Permission Denied
```
error: Permission denied: ./Scripts/run-qemu-tests.sh
```

**Solutions:**
```bash
# Fix script permissions
chmod +x Scripts/run-qemu-tests.sh

# Verify permissions
ls -la Scripts/run-qemu-tests.sh

# Should show: -rwxr-xr-x (executable permissions)
```

#### QEMU Server Build Failures
```
error: No such file or directory: QEMUTestServer
```

**Solutions:**
```bash
# Build QEMU test server explicitly
swift build --product QEMUTestServer

# Verify build output
ls -la .build/debug/QEMUTestServer

# Check Package.swift for QEMUTestServer target
.executableTarget(
    name: "QEMUTestServer",
    dependencies: ["USBIPDCore", "Common"]
)
```

### Network Connectivity Issues

#### Port Conflicts
```
error: Address already in use (bind failed)
```

**Solutions:**
```bash
# Check for processes using the port
lsof -i :3240  # Default USB/IP port

# Kill conflicting processes
sudo kill -9 <PID>

# Use different port for testing
export USBIP_TEST_PORT=3241
./Scripts/run-qemu-tests.sh
```

#### Connection Refused
```
error: Connection refused
```

**Solutions:**
```bash
# Check if server is running
ps aux | grep QEMUTestServer

# Verify network configuration
netstat -an | grep 3240

# Check firewall settings
sudo pfctl -sr | grep 3240

# Test local connectivity
telnet localhost 3240
```

## Performance Issues

### Slow CI Execution

#### Cache Misses
```
warning: CI execution time exceeds 10 minutes
```

**Diagnosis:**
```bash
# Check cache hit rates in CI logs
# Look for "Cache restored from key:" vs "Cache not found"

# Verify cache configuration in workflow
- uses: actions/cache@v3
  with:
    path: |
      .build
      ~/Library/Caches/org.swift.swiftpm
    key: ${{ runner.os }}-spm-${{ hashFiles('Package.resolved') }}
```

**Solutions:**
1. **Optimize cache keys**: Use more specific cache keys
2. **Reduce cache size**: Exclude unnecessary files
3. **Parallel execution**: Ensure jobs run in parallel
4. **Incremental builds**: Use build caching effectively

#### Slow Tests
```
warning: Test execution takes longer than expected
```

**Solutions:**
```swift
// Profile slow tests
func testPerformance() {
    measure {
        // Code to measure
        performExpensiveOperation()
    }
}

// Optimize test setup
override func setUp() {
    super.setUp()
    // Move expensive setup to class-level setUp if shared
}

// Use mock objects for external dependencies
let mockService = MockNetworkService()
// Instead of real network calls
```

## Swift and macOS Version Updates

### Swift Version Updates

#### Updating to New Swift Version

1. **Update Package.swift tools version:**
```swift
// swift-tools-version:5.9
// Update to new version
```

2. **Test locally:**
```bash
swift --version  # Verify new version
swift build      # Test compilation
swift test       # Test execution
```

3. **Handle breaking changes:**
```swift
// Example: Concurrency changes in Swift 5.9
@MainActor
class ViewModelClass {
    // Properties and methods
}

// Update async/await usage
func updateData() async throws {
    let data = try await fetchData()
    await MainActor.run {
        self.updateUI(with: data)
    }
}
```

4. **Update CI if needed:**
```yaml
# Usually not needed as CI uses 'latest'
- name: Setup Swift
  uses: swift-actions/setup-swift@v1
  with:
    swift-version: '5.9'  # Only if specific version required
```

### macOS Version Updates

#### Updating Minimum Deployment Target

1. **Update Package.swift:**
```swift
platforms: [
    .macOS(.v14),  // Update from .v13
],
```

2. **Handle new APIs:**
```swift
// Use availability checks
if #available(macOS 14.0, *) {
    // Use new macOS 14 APIs
    newAPI()
} else {
    // Fallback for older versions
    legacyAPI()
}
```

3. **Update CI runner (if needed):**
```yaml
# CI automatically uses macos-latest
# Only update if specific version required
runs-on: macos-14  # Instead of macos-latest
```

#### Handling Deprecated APIs

```swift
// Replace deprecated APIs
// Old:
let result = deprecatedFunction()

// New:
let result = newReplacementFunction()

// With availability check:
let result: ResultType
if #available(macOS 14.0, *) {
    result = newReplacementFunction()
} else {
    result = deprecatedFunction()
}
```

### Version Compatibility Testing

```bash
# Test with multiple Swift versions (if needed)
xcrun --toolchain swift-5.8-RELEASE swift build
xcrun --toolchain swift-5.9-RELEASE swift build

# Test deployment target compatibility
swift build -Xswiftc -target -Xswiftc x86_64-apple-macos13.0
```

## Cache Issues

### Cache Corruption

#### Symptoms
- Inconsistent build results
- "No such module" errors that resolve after clean build
- Unexplained compilation failures

#### Solutions
```bash
# Clear all caches locally
swift package clean
rm -rf .build
rm -rf ~/Library/Caches/org.swift.swiftpm

# Clear derived data (if using Xcode)
rm -rf ~/Library/Developer/Xcode/DerivedData

# In CI, cache keys can be updated to force refresh
# Update the cache key in workflow file:
key: ${{ runner.os }}-spm-v2-${{ hashFiles('Package.resolved') }}
#                        ^^^ increment version
```

### Cache Size Issues

#### Large Cache Sizes
```bash
# Check cache size
du -sh .build
du -sh ~/Library/Caches/org.swift.swiftpm

# Optimize cache by excluding unnecessary files
# In workflow file:
path: |
  .build/checkouts
  .build/repositories
  ~/Library/Caches/org.swift.swiftpm
# Exclude .build/debug and .build/release (large, rebuild quickly)
```

## Branch Protection Issues

### Status Check Failures

#### Required Checks Not Running
```
error: Required status check "lint" has not run
```

**Solutions:**
1. **Check workflow triggers:**
```yaml
on:
  pull_request:
    branches: [ main ]  # Ensure correct branch
  push:
    branches: [ main ]
```

2. **Verify job names match protection rules:**
```yaml
jobs:
  lint:  # Must match required status check name
    name: Code Quality (SwiftLint)
```

3. **Update branch protection settings:**
```bash
# Use the setup script
./.github/scripts/setup-branch-protection.sh

# Or manually update via GitHub UI:
# Settings > Branches > Branch protection rules
```

### Bypass Procedures

#### Emergency Merges
When CI is broken and urgent fixes are needed:

1. **Document the reason:**
   - Create issue explaining the emergency
   - Document what checks are being bypassed
   - Explain why the bypass is necessary

2. **Get maintainer approval:**
   - Request review from repository maintainers
   - Explain the urgency and impact
   - Commit to fixing CI in follow-up PR

3. **Follow-up actions:**
   - Create issue to fix CI problems
   - Schedule fix within 24 hours
   - Update team on resolution

## Emergency Procedures

### Complete CI Failure

#### When All Jobs Fail
1. **Check GitHub Actions status:**
   - Visit https://www.githubstatus.com/
   - Look for GitHub Actions incidents

2. **Verify workflow syntax:**
```bash
# Use GitHub CLI to validate workflow
gh workflow list
gh workflow view ci.yml
```

3. **Test workflow locally:**
```bash
# Use act to run GitHub Actions locally
brew install act
act -j lint  # Test specific job
```

### Critical Security Issues

#### Secrets Exposure
If secrets are accidentally exposed:

1. **Immediately revoke exposed secrets**
2. **Update repository secrets**
3. **Force push to remove from history (if needed)**
4. **Audit access logs**

#### Malicious Code in Dependencies
1. **Pin dependency versions in Package.swift**
2. **Review Package.resolved for unexpected changes**
3. **Use dependency scanning tools**

### Recovery Procedures

#### Restoring from Backup
```bash
# If main branch is corrupted
git checkout -b recovery-branch <last-known-good-commit>
git push origin recovery-branch

# Create PR to restore main branch
# After review, force push to main (with team approval)
git push --force-with-lease origin recovery-branch:main
```

#### Rebuilding CI from Scratch
1. **Backup current workflow:**
```bash
cp .github/workflows/ci.yml .github/workflows/ci.yml.backup
```

2. **Start with minimal workflow:**
```yaml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - run: swift build
```

3. **Gradually add complexity:**
   - Add linting
   - Add testing
   - Add caching
   - Add parallel execution

## Getting Additional Help

### Internal Resources
1. **Check this troubleshooting guide first**
2. **Review CI job logs for specific error messages**
3. **Test locally using exact CI commands**
4. **Check recent changes that might have caused issues**

### External Resources
1. **GitHub Actions Documentation**: https://docs.github.com/en/actions
2. **Swift Package Manager Guide**: https://swift.org/package-manager/
3. **SwiftLint Documentation**: https://github.com/realm/SwiftLint
4. **GitHub Actions Status**: https://www.githubstatus.com/

### Escalation Process
1. **Try local reproduction first**
2. **Check this guide for solutions**
3. **Search existing issues in the repository**
4. **Create detailed issue with:**
   - Error messages
   - Steps to reproduce
   - Local environment details
   - CI job logs (relevant portions)

### Maintainer Contact
For urgent issues or when standard troubleshooting doesn't resolve the problem:
1. **Create GitHub issue with "urgent" label**
2. **Include full error logs and reproduction steps**
3. **Tag repository maintainers if critical**
4. **Provide timeline requirements for resolution**

---

*This guide is maintained alongside the CI workflow. When updating the workflow, please update this guide accordingly.*