# CI Troubleshooting Guide

This guide provides comprehensive solutions for common GitHub Actions CI issues in the usbipd-mac project.

## Table of Contents

- [Quick Diagnosis](#quick-diagnosis)
- [SwiftLint Issues](#swiftlint-issues)
- [Build Failures](#build-failures)
- [Test Failures](#test-failures)
- [Integration Test Issues](#integration-test-issues)
- [Environment and Version Issues](#environment-and-version-issues)
- [Performance and Timeout Issues](#performance-and-timeout-issues)
- [Updating Swift and macOS Versions](#updating-swift-and-macos-versions)
- [Cache Issues](#cache-issues)
- [Branch Protection Issues](#branch-protection-issues)

## Quick Diagnosis

When CI fails, start with these quick checks:

1. **Check the failing job**: Look at which specific job failed (lint, build, test, integration-test)
2. **Review the error summary**: Each job provides a summary section with common causes
3. **Run locally first**: Always reproduce the issue locally before investigating CI-specific problems
4. **Check recent changes**: Consider if recent dependency updates or configuration changes might be the cause

## SwiftLint Issues

### Common SwiftLint Failures

#### Issue: SwiftLint Installation Fails
```
Error: Failed to install SwiftLint via Homebrew
```

**Diagnosis:**
- Homebrew installation issues on the runner
- Network connectivity problems
- SwiftLint package availability issues

**Solutions:**
1. **Check Homebrew status**: The issue is usually temporary
2. **Retry the workflow**: Often resolves transient network issues
3. **Update SwiftLint cache key**: If persistent, update the cache key in `.github/workflows/ci.yml`:
   ```yaml
   key: ${{ runner.os }}-swiftlint-v2-${{ hashFiles('.swiftlint.yml') }}
   ```

#### Issue: SwiftLint Rule Violations
```
error: Line Length Violation: Line should be 120 characters or less (line_length)
warning: Trailing Whitespace: Lines should not have trailing whitespace (trailing_whitespace)
```

**Diagnosis:**
- Code doesn't meet project style guidelines
- New SwiftLint rules were added to `.swiftlint.yml`
- Auto-formatting tools weren't used

**Solutions:**
1. **Run SwiftLint locally**:
   ```bash
   # Install SwiftLint if needed
   brew install swiftlint
   
   # Check violations
   swiftlint lint --strict
   
   # Auto-fix violations where possible
   swiftlint --fix
   ```

2. **Common fixes**:
   - Remove trailing whitespace
   - Break long lines (120 character limit)
   - Add missing documentation comments for public APIs
   - Fix indentation and spacing issues

3. **Update SwiftLint configuration** (if rules are too strict):
   ```yaml
   # .swiftlint.yml
   disabled_rules:
     - line_length  # Temporarily disable if needed
   
   line_length:
     warning: 120
     error: 150
   ```

#### Issue: SwiftLint Configuration Errors
```
error: Configuration file contains invalid keys
```

**Diagnosis:**
- Invalid YAML syntax in `.swiftlint.yml`
- Unsupported SwiftLint rules or options
- Version mismatch between local and CI SwiftLint

**Solutions:**
1. **Validate YAML syntax**:
   ```bash
   # Check YAML syntax
   python -c "import yaml; yaml.safe_load(open('.swiftlint.yml'))"
   ```

2. **Check SwiftLint version compatibility**:
   ```bash
   # Check local version
   swiftlint version
   
   # Update to match CI (latest)
   brew upgrade swiftlint
   ```

3. **Test configuration locally**:
   ```bash
   swiftlint lint --config .swiftlint.yml --strict
   ```

## Build Failures

### Common Build Issues

#### Issue: Swift Package Resolution Fails
```
error: failed to resolve dependencies
```

**Diagnosis:**
- Network connectivity issues
- Invalid Package.swift configuration
- Dependency version conflicts
- Missing or moved repositories

**Solutions:**
1. **Check Package.swift syntax**:
   ```bash
   swift package dump-package
   ```

2. **Resolve dependencies locally**:
   ```bash
   swift package clean
   swift package resolve
   swift package show-dependencies
   ```

3. **Update dependency versions**:
   ```bash
   swift package update
   ```

4. **Check for dependency conflicts**:
   - Review Package.resolved for version conflicts
   - Ensure all dependencies support the same Swift version

#### Issue: Swift Compilation Errors
```
error: cannot find 'SomeType' in scope
error: module 'SomeModule' not found
```

**Diagnosis:**
- Missing imports
- Typos in type names
- Module visibility issues
- Swift version compatibility problems

**Solutions:**
1. **Check imports and module structure**:
   ```swift
   import Foundation
   import SystemExtensions
   // Ensure all required imports are present
   ```

2. **Verify module targets in Package.swift**:
   ```swift
   .target(
       name: "USBIPDCore",
       dependencies: [
           "Common",
           // Ensure all dependencies are listed
       ]
   )
   ```

3. **Test compilation locally**:
   ```bash
   swift build --verbose
   ```

#### Issue: Platform Compatibility Errors
```
error: 'SomeAPI' is only available in macOS 12.0 or newer
```

**Diagnosis:**
- Using APIs not available in minimum deployment target
- Missing availability checks
- Incorrect platform version specifications

**Solutions:**
1. **Add availability checks**:
   ```swift
   if #available(macOS 12.0, *) {
       // Use newer API
   } else {
       // Fallback implementation
   }
   ```

2. **Update minimum deployment target** in Package.swift:
   ```swift
   platforms: [
       .macOS(.v12)  // Update as needed
   ]
   ```

3. **Use alternative APIs** for older versions

## Test Failures

### Common Test Issues

#### Issue: Unit Test Failures
```
Test Case 'TestClass.testMethod' failed
XCTAssertEqual failed: ("expected") is not equal to ("actual")
```

**Diagnosis:**
- Logic errors in implementation
- Incorrect test expectations
- Test data or mock setup issues
- Race conditions in async tests

**Solutions:**
1. **Run tests locally with verbose output**:
   ```bash
   swift test --verbose --filter TestClass.testMethod
   ```

2. **Debug test failures**:
   ```bash
   # Run specific test suite
   swift test --filter USBIPDCoreTests
   
   # Run with debugging
   swift test --enable-test-discovery --verbose
   ```

3. **Check test data and mocks**:
   - Verify test data files are included in the package
   - Ensure mock objects are properly configured
   - Check for hardcoded paths or assumptions

4. **Fix async test issues**:
   ```swift
   func testAsyncOperation() async throws {
       let expectation = XCTestExpectation(description: "Async operation")
       
       // Use proper async/await patterns
       let result = await someAsyncOperation()
       XCTAssertEqual(result, expectedValue)
       
       expectation.fulfill()
       await fulfillment(of: [expectation], timeout: 5.0)
   }
   ```

#### Issue: Test Environment Setup Failures
```
error: Test bundle could not be loaded
```

**Diagnosis:**
- Missing test dependencies
- Incorrect test target configuration
- Test resource loading issues

**Solutions:**
1. **Verify test target configuration** in Package.swift:
   ```swift
   .testTarget(
       name: "USBIPDCoreTests",
       dependencies: ["USBIPDCore"],
       resources: [
           .process("TestData")  // Include test resources
       ]
   )
   ```

2. **Check test resource loading**:
   ```swift
   // Correct way to load test resources
   let bundle = Bundle.module
   let testDataURL = bundle.url(forResource: "test-data", withExtension: "json")
   ```

3. **Rebuild test targets**:
   ```bash
   swift package clean
   swift build --build-tests
   swift test
   ```

## Integration Test Issues

### QEMU Test Server Issues

#### Issue: QEMU Test Server Build Fails
```
error: failed to build product 'QEMUTestServer'
```

**Diagnosis:**
- Missing QEMUTestServer target in Package.swift
- Compilation errors in QEMU test server code
- Missing dependencies for QEMU functionality

**Solutions:**
1. **Verify QEMUTestServer target exists** in Package.swift:
   ```swift
   .executableTarget(
       name: "QEMUTestServer",
       dependencies: ["USBIPDCore", "Common"]
   )
   ```

2. **Build QEMU test server locally**:
   ```bash
   swift build --product QEMUTestServer
   .build/debug/QEMUTestServer --help
   ```

3. **Check QEMU test server dependencies**:
   - Ensure all required modules are imported
   - Verify network and system dependencies are available

#### Issue: QEMU Test Script Fails
```
error: ./Scripts/run-qemu-tests.sh: Permission denied
```

**Diagnosis:**
- Script permissions not set correctly
- Script execution errors
- Missing script dependencies

**Solutions:**
1. **Fix script permissions**:
   ```bash
   chmod +x Scripts/run-qemu-tests.sh
   ```

2. **Test script locally**:
   ```bash
   ./Scripts/run-qemu-tests.sh
   ```

3. **Debug script issues**:
   ```bash
   # Run with debugging
   bash -x Scripts/run-qemu-tests.sh
   ```

4. **Check script dependencies**:
   - Ensure QEMU test server is built
   - Verify network ports are available
   - Check for required system tools

#### Issue: Integration Test Network Failures
```
error: Connection refused
error: Network timeout
```

**Diagnosis:**
- Port conflicts on CI runner
- Network connectivity issues
- Timing issues in test setup

**Solutions:**
1. **Use dynamic port allocation**:
   ```swift
   // Use system-assigned ports instead of fixed ports
   let server = try TCPServer(port: 0)  // 0 = system assigns port
   let actualPort = server.localPort
   ```

2. **Add proper test timeouts and retries**:
   ```swift
   func testNetworkConnection() async throws {
       let maxRetries = 3
       for attempt in 1...maxRetries {
           do {
               try await connectToServer()
               break
           } catch {
               if attempt == maxRetries { throw error }
               try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
           }
       }
   }
   ```

3. **Check for port conflicts**:
   ```bash
   # Check if port is in use
   lsof -i :3240
   
   # Use different port ranges for tests
   ```

## Environment and Version Issues

### Swift Version Issues

#### Issue: Swift Version Compatibility
```
error: package at '...' requires minimum Swift version 5.8.0
```

**Diagnosis:**
- CI using older Swift version than required
- Local development using different Swift version
- Dependencies requiring newer Swift features

**Solutions:**
1. **Check current Swift version in CI**:
   - Look at the "Verify Build Environment" step output
   - Compare with local version: `swift --version`

2. **Update Swift version requirement** in Package.swift:
   ```swift
   // swift-tools-version:5.8
   import PackageDescription
   
   let package = Package(
       name: "usbipd-mac",
       platforms: [.macOS(.v12)],
       // ...
   )
   ```

3. **Use specific Swift version in CI** (if needed):
   ```yaml
   - name: Setup Swift Environment
     uses: swift-actions/setup-swift@v1
     with:
       swift-version: '5.8'  # Specify exact version if needed
   ```

#### Issue: macOS Version Compatibility
```
error: 'SomeAPI' is only available in macOS 13.0 or newer
```

**Diagnosis:**
- Using APIs not available in CI runner's macOS version
- Minimum deployment target too low
- Version availability checks missing

**Solutions:**
1. **Check CI runner macOS version**:
   - Look at the environment information in job output
   - Current CI uses `macos-latest` (typically macOS 13+)

2. **Add proper availability checks**:
   ```swift
   @available(macOS 13.0, *)
   func useNewerAPI() {
       // Implementation using newer APIs
   }
   
   func compatibleImplementation() {
       if #available(macOS 13.0, *) {
           useNewerAPI()
       } else {
           // Fallback for older versions
       }
   }
   ```

3. **Update minimum deployment target**:
   ```swift
   platforms: [
       .macOS(.v13)  // Match CI runner capabilities
   ]
   ```

### GitHub Actions Runner Issues

#### Issue: Runner Out of Disk Space
```
error: No space left on device
```

**Diagnosis:**
- Large build artifacts
- Cache accumulation
- Dependency bloat

**Solutions:**
1. **Clean up build artifacts**:
   ```yaml
   - name: Clean up build artifacts
     run: |
       swift package clean
       rm -rf .build
   ```

2. **Optimize cache usage**:
   ```yaml
   - name: Cache Swift packages
     uses: actions/cache@v3
     with:
       path: |
         .build
         ~/Library/Caches/org.swift.swiftpm
       key: ${{ runner.os }}-swift-${{ hashFiles('Package.swift') }}
       restore-keys: |
         ${{ runner.os }}-swift-
   ```

3. **Use cache cleanup**:
   ```yaml
   - name: Clean old caches
     run: |
       # Remove old cache entries if needed
       rm -rf ~/Library/Caches/org.swift.swiftpm/repositories
   ```

## Performance and Timeout Issues

### Slow CI Execution

#### Issue: CI Takes Too Long (>10 minutes)
```
The job running on runner GitHub Actions X has exceeded the maximum execution time of 360 minutes.
```

**Diagnosis:**
- Inefficient dependency resolution
- Large test suites
- Missing cache optimization
- Network issues

**Solutions:**
1. **Optimize dependency caching**:
   ```yaml
   - name: Cache Swift packages
     uses: actions/cache@v3
     with:
       path: |
         .build
         ~/Library/Caches/org.swift.swiftpm
         ~/Library/org.swift.swiftpm
       key: ${{ runner.os }}-swift-${{ hashFiles('Package.swift', 'Package.resolved') }}
   ```

2. **Use parallel test execution**:
   ```bash
   swift test --parallel --verbose
   ```

3. **Profile slow tests**:
   ```bash
   # Identify slow tests
   swift test --verbose 2>&1 | grep "Test Case.*passed"
   ```

4. **Optimize build configuration**:
   ```bash
   # Use release mode for performance testing
   swift build -c release
   ```

#### Issue: Network Timeouts
```
error: timeout while fetching repository
```

**Diagnosis:**
- Network connectivity issues
- Large dependency downloads
- GitHub API rate limiting

**Solutions:**
1. **Add retry logic** for network operations:
   ```yaml
   - name: Resolve Dependencies with Retry
     run: |
       for i in {1..3}; do
         if swift package resolve; then
           break
         fi
         echo "Attempt $i failed, retrying..."
         sleep 10
       done
   ```

2. **Use dependency caching** to reduce network usage

3. **Check for large dependencies** and consider alternatives

## Updating Swift and macOS Versions

This section addresses requirements 4.3 and 4.4 for keeping the CI pipeline current with latest versions.

### Updating to Latest Swift Version

#### When to Update
- New stable Swift version is released
- Dependencies require newer Swift version
- Security updates or critical bug fixes
- Quarterly maintenance schedule

#### Update Process

1. **Check Swift version compatibility**:
   ```bash
   # Check current project Swift version requirement
   head -1 Package.swift
   
   # Check available Swift versions
   swift --version
   ```

2. **Update Package.swift**:
   ```swift
   // swift-tools-version:5.9  // Update to latest
   import PackageDescription
   
   let package = Package(
       name: "usbipd-mac",
       platforms: [.macOS(.v12)],  // Update if needed
       // ...
   )
   ```

3. **Test locally before CI update**:
   ```bash
   # Clean build with new Swift version
   swift package clean
   swift build
   swift test
   ```

4. **Update CI workflow** (if using specific version):
   ```yaml
   - name: Setup Swift Environment
     uses: swift-actions/setup-swift@v1
     with:
       swift-version: 'latest'  # Or specific version like '5.9'
   ```

5. **Test CI changes**:
   - Create a test branch
   - Push changes and verify CI passes
   - Check all jobs complete successfully

#### Common Swift Update Issues

**Issue: Deprecated API Usage**
```
warning: 'oldAPI' is deprecated in Swift 5.9
```

**Solutions:**
1. **Update deprecated APIs**:
   ```swift
   // Old way
   let result = oldAPI()
   
   // New way
   let result = newAPI()
   ```

2. **Use compiler directives** for gradual migration:
   ```swift
   #if swift(>=5.9)
   let result = newAPI()
   #else
   let result = oldAPI()
   #endif
   ```

**Issue: Breaking Changes**
```
error: cannot convert value of type 'X' to expected argument type 'Y'
```

**Solutions:**
1. **Review Swift migration guide** for the new version
2. **Update code to match new requirements**
3. **Use Swift's migration tools** when available

### Updating to Latest macOS Version

#### When to Update
- New macOS version available on GitHub Actions
- Dependencies require newer macOS APIs
- Security updates or performance improvements
- Bi-annual maintenance schedule

#### Update Process

1. **Check available macOS versions**:
   - Visit [GitHub Actions runner images](https://github.com/actions/runner-images)
   - Check `macos-latest` current version
   - Review `macos-13`, `macos-14` specific versions

2. **Update CI workflow**:
   ```yaml
   jobs:
     lint:
       runs-on: macos-latest  # Always use latest
       # OR use specific version:
       # runs-on: macos-14
   ```

3. **Update minimum deployment target** (if needed):
   ```swift
   platforms: [
       .macOS(.v13)  // Update to match CI capabilities
   ]
   ```

4. **Test compatibility**:
   ```bash
   # Test on local macOS version
   swift build
   swift test
   ./Scripts/run-qemu-tests.sh
   ```

#### Common macOS Update Issues

**Issue: API Availability Errors**
```
error: 'newAPI' is only available in macOS 14.0 or newer
```

**Solutions:**
1. **Add availability checks**:
   ```swift
   @available(macOS 14.0, *)
   func useNewAPI() {
       // Use new API
   }
   
   func compatibleImplementation() {
       if #available(macOS 14.0, *) {
           useNewAPI()
       } else {
           // Fallback implementation
       }
   }
   ```

2. **Update deployment target**:
   ```swift
   platforms: [
       .macOS(.v14)  // Require newer macOS
   ]
   ```

**Issue: Deprecated System APIs**
```
warning: 'oldSystemAPI' was deprecated in macOS 14.0
```

**Solutions:**
1. **Migrate to new system APIs**
2. **Use feature detection** instead of version checks where possible
3. **Maintain backward compatibility** if supporting older versions

### Version Update Checklist

Before updating Swift or macOS versions:

- [ ] **Local Testing**: Verify project builds and tests pass locally
- [ ] **Dependency Compatibility**: Check all dependencies support new versions
- [ ] **API Migration**: Update any deprecated or changed APIs
- [ ] **Documentation**: Update README and documentation with new requirements
- [ ] **CI Testing**: Test changes on a feature branch first
- [ ] **Rollback Plan**: Ensure you can revert if issues arise
- [ ] **Team Communication**: Notify team of version requirements changes

### Handling Version Incompatibilities

When new versions cause issues:

1. **Identify the specific problem**:
   ```bash
   # Get detailed error information
   swift build --verbose
   swift test --verbose
   ```

2. **Check for known issues**:
   - Review Swift release notes
   - Check dependency issue trackers
   - Search GitHub Actions community discussions

3. **Implement workarounds**:
   ```swift
   // Conditional compilation for version differences
   #if swift(>=5.9)
   // New implementation
   #else
   // Legacy implementation
   #endif
   ```

4. **Consider pinning versions temporarily**:
   ```yaml
   - name: Setup Swift Environment
     uses: swift-actions/setup-swift@v1
     with:
       swift-version: '5.8'  # Pin to working version temporarily
   ```

5. **Plan migration strategy**:
   - Create migration timeline
   - Update dependencies first
   - Migrate code incrementally
   - Test thoroughly at each step

## Cache Issues

### Cache Corruption

#### Issue: Build Cache Corruption
```
error: corrupt cache entry
error: failed to load cached dependencies
```

**Diagnosis:**
- Cache corruption due to interrupted builds
- Version mismatches in cached data
- Disk space issues during caching

**Solutions:**
1. **Clear cache manually**:
   ```yaml
   - name: Clear corrupted cache
     run: |
       rm -rf .build
       rm -rf ~/Library/Caches/org.swift.swiftpm
   ```

2. **Update cache keys** to force refresh:
   ```yaml
   key: ${{ runner.os }}-swift-v2-${{ hashFiles('Package.swift') }}
   ```

3. **Use cache restore fallbacks**:
   ```yaml
   restore-keys: |
     ${{ runner.os }}-swift-v2-
     ${{ runner.os }}-swift-
   ```

### Cache Performance Issues

#### Issue: Cache Not Being Used
```
Cache not found for input keys: ...
```

**Diagnosis:**
- Cache key changes too frequently
- Cache size limits exceeded
- Incorrect cache paths

**Solutions:**
1. **Optimize cache keys**:
   ```yaml
   # Use stable cache keys
   key: ${{ runner.os }}-swift-${{ hashFiles('Package.swift', 'Package.resolved') }}
   ```

2. **Check cache paths**:
   ```yaml
   path: |
     .build
     ~/Library/Caches/org.swift.swiftpm
     ~/Library/org.swift.swiftpm  # Include all relevant paths
   ```

3. **Monitor cache usage**:
   - Check cache hit rates in CI logs
   - Verify cache size limits aren't exceeded

## Branch Protection Issues

### Status Check Failures

#### Issue: Required Checks Not Running
```
Some checks haven't run on this PR yet
```

**Diagnosis:**
- Workflow not triggered properly
- Branch protection rules misconfigured
- GitHub Actions permissions issues

**Solutions:**
1. **Verify workflow triggers**:
   ```yaml
   on:
     push:
       branches: [ main ]
     pull_request:
       branches: [ main ]
   ```

2. **Check branch protection settings**:
   ```bash
   # Use provided validation script
   ./.github/scripts/validate-branch-protection.sh
   ```

3. **Re-run failed checks**:
   - Use "Re-run failed jobs" in GitHub UI
   - Push new commit to trigger checks

#### Issue: Checks Pass But Merge Blocked
```
Merging is blocked due to failing status checks
```

**Diagnosis:**
- Status check names don't match branch protection rules
- Additional required checks configured
- Stale branch protection settings

**Solutions:**
1. **Check status check names** match exactly:
   ```yaml
   # In workflow
   name: Code Quality (SwiftLint)
   
   # Must match branch protection rule exactly
   ```

2. **Update branch protection rules**:
   ```bash
   # Use setup script to reconfigure
   ./.github/scripts/setup-branch-protection.sh
   ```

3. **Verify all required checks** are listed in branch protection

## Getting Additional Help

If these solutions don't resolve your issue:

1. **Check CI job logs** for detailed error messages
2. **Run the same commands locally** to reproduce the issue
3. **Review recent changes** that might have introduced the problem
4. **Check GitHub Actions status** for platform-wide issues
5. **Consult project maintainers** for project-specific guidance

### Useful Commands for Debugging

```bash
# Complete local CI simulation
echo "=== SwiftLint Check ==="
swiftlint lint --strict

echo "=== Build Check ==="
swift package clean
swift build --verbose

echo "=== Unit Tests ==="
swift test --verbose --parallel

echo "=== Integration Tests ==="
swift build --product QEMUTestServer
./Scripts/run-qemu-tests.sh
swift test --filter IntegrationTests --verbose

echo "=== Environment Info ==="
swift --version
sw_vers
xcodebuild -version
```

### Emergency Procedures

If CI is completely broken and blocking development:

1. **Temporarily disable failing checks**:
   - Comment out problematic jobs in workflow
   - Reduce branch protection requirements temporarily

2. **Use manual merge** (with approval):
   - Require admin approval for emergency merges
   - Document the bypass reason

3. **Create hotfix workflow**:
   - Simplified workflow for critical fixes
   - Restore full CI after issue resolution

Remember: Always restore full CI protection as soon as issues are resolved.