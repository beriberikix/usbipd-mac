# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

usbipd-mac is a macOS USB/IP protocol implementation for sharing USB devices over IP networks. The project is built using Swift Package Manager and targets macOS 11+.

**Main Repository**: https://github.com/beriberikix/usbipd-mac  
**Homebrew Tap Repository**: https://github.com/beriberikix/homebrew-usbipd-mac

## Architecture

The project is structured as a multi-target Swift package:

### Core Targets
- **USBIPDCore**: Core USB/IP protocol implementation and device management
  - `Device/`: IOKit-based USB device discovery and monitoring
  - `Network/`: TCP server and client connection handling
  - `Protocol/`: USB/IP message encoding/decoding and request processing
- **USBIPDCLI**: Command-line interface executable (`usbipd` binary)
- **Common**: Shared utilities (logging, error handling)
- **SystemExtension**: macOS System Extension integration
- **QEMUTestServer**: QEMU validation test server

### Test Structure

`Package.swift` declares two test targets, and they are the whole suite:

- **Tests/USBIPDCoreTests/** — core protocol, device, and network tests
- **Tests/USBIPDCLITests/** — CLI behaviour

Both also compile **Tests/SharedUtilities/** via their `sources:` list.

Three further targets are declared but commented out as "temporarily disabled":
`IntegrationTests`, `SystemExtensionTests`, `QEMUIntegrationTests`. Alongside them
`Tests/TestMocks/`, `Tests/ProductionTests/` and `Tests/PerformanceTests/` are compiled
by nothing. None of it has built in about a year — do not cite coverage from it without
reviving the target first. See `Documentation/development/testing-strategy.md`.

## Development Commands

### Build
```bash
# Standard build
swift build

# Build specific product
swift build --product QEMUTestServer

# Xcode build
xcodebuild -scheme usbipd-mac build
```

### Testing

```bash
# Run the test suite
swift test --parallel

# Run one target or one test
swift test --filter USBIPDCoreTests
swift test --filter USBIPDCoreTests.USBIPProtocolTests
```

Only two test targets exist in `Package.swift`: `USBIPDCLITests` and
`USBIPDCoreTests`. There is no tiered development/CI/production test system — the
scripts that claimed to provide one filtered on target names that were never declared,
so they matched nothing and exited 0. They were removed in 2026-08 along with the CI
step that called them. `swift test` is the whole story.

Note that `swift test` needs XCTest, which ships with Xcode. A machine with only the
Command Line Tools cannot run it (`error: no such module 'XCTest'`); use CI, which runs
on `macos-latest` with full Xcode.

### Code Quality
```bash
# Run SwiftLint (strict mode like CI)
swiftlint lint --strict

# Auto-fix violations
swiftlint --fix
```

### Full CI Validation Locally
```bash
# Complete validation sequence (matches consolidated CI pipeline)
swiftlint lint --strict                      # Code quality validation
swift build --verbose                        # Build validation  
swift test --parallel                        # Test suite

# Full production validation for release preparation
swiftlint lint --strict                      # Code quality validation
swift build --verbose                        # Build validation

# Validate specific workflow components locally
# (These match the consolidated CI workflow jobs)

# 1. Code Quality Job validation
swiftlint lint --strict --reporter xcode    # Matches CI swiftlint-validation action

# 2. Build Validation Job validation  
swift package resolve                        # Dependency resolution
swift build --verbose                        # Project compilation

# 3. Test Suite Job validation (environment-specific)

# 4. Release Validation (when preparing releases)
swift build --configuration release         # Release build validation
# Note: Full release validation includes version checks and artifact validation
```

### Working with Consolidated CI Workflows

When making changes that might affect CI workflows:

```bash
# Test changes against CI workflow locally before pushing
swiftlint lint --strict && swift build --verbose && swift test --parallel

# For release-related changes, test with production environment
swiftlint lint --strict && swift build --verbose && swift test --parallel

# Check if changes affect security scanning
# (Security workflow runs on Package.swift, Package.resolved, and Sources/ changes)
find Sources -name "*.swift" -exec grep -l "secret\|password\|key" {} +

# Validate test environment setup before CI runs
```

### AI Assistant Guidance for CI Workflows

When working with the consolidated CI system:

1. **Code Quality**: Always run `swiftlint lint --strict` before committing to catch issues early
2. **Build Validation**: Use `swift build --verbose` to get detailed build information
3. **Test Execution**: Use environment-specific test scripts that match CI workflow job matrix
4. **Release Preparation**: Use production environment tests for release validation
5. **Security Awareness**: Be mindful of changes to dependencies and source code that trigger security scans
6. **Workflow Monitoring**: Monitor GitHub Actions for CI status and investigate failures promptly

The consolidated architecture reduces complexity while maintaining comprehensive validation coverage.

## Key Implementation Details

### Device Discovery
The IOKit-based device discovery system in `Sources/USBIPDCore/Device/` handles USB device enumeration and monitoring. Key files:
- `IOKitDeviceDiscovery.swift`: Main discovery interface
- `DeviceMonitor.swift`: Device state change monitoring

### Network Layer
TCP server implementation in `Sources/USBIPDCore/Network/` manages client connections and protocol communication.

### USB/IP Protocol
Protocol implementation in `Sources/USBIPDCore/Protocol/` handles message encoding/decoding according to USB/IP specification.

## SwiftLint Configuration

The project uses a comprehensive SwiftLint configuration (`.swiftlint.yml`) with:
- Strict enforcement in CI (warnings treated as errors)
- Many formatting rules disabled to focus on core issues
- Extensive opt-in rules for code quality
- Test-specific rule relaxations

## Testing Strategy

The project uses a three-tier environment-based testing approach:

### Development Environment
- **Purpose**: Rapid feedback during active development
- **Execution time**: <1 minute
- **Coverage**: Unit tests with comprehensive mocking
- **Use case**: Local development, IDE integration

### CI Environment  
- **Purpose**: Automated validation in GitHub Actions
- **Execution time**: <3 minutes
- **Coverage**: Protocol and network tests without hardware dependencies
- **Use case**: Pull request validation, automated testing

### Production Environment
- **Purpose**: Complete validation for release preparation
- **Execution time**: <10 minutes
- **Coverage**: QEMU integration, hardware validation, System Extension testing
- **Use case**: Release candidate validation, comprehensive testing
- **QEMU Integration**: Full VM-based testing with protocol validation

### Key Features
- Environment-specific mock libraries for reliable testing
- Conditional hardware detection and graceful degradation
- QEMU-based end-to-end integration testing infrastructure
- Comprehensive test reporting and environment validation
- Parallel test execution for optimal performance

## Scripts

Located in `Scripts/` directory:

### Test Execution Scripts

### Test Infrastructure Scripts
- `qemu-test-validation.sh`: QEMU server validation utilities
- `validate-usb-entitlements.sh`: Measures which entitlement actually gates USB device claiming (macOS only, see `Documentation/development/entitlement-validation.md`)

### Release and Distribution Scripts
- `prepare-release.sh`: Comprehensive release preparation and validation
- `rollback-release.sh`: Release rollback and cleanup utilities

### Usage Examples
```bash
# Quick development feedback
swift test --parallel

# Validate environment before testing

# Generate comprehensive test report
swift test --parallel

# Test repository dispatch workflow

# Prepare and validate release
./Scripts/prepare-release.sh --dry-run v1.2.3

# Validate release artifacts
```

## QEMU Testing Infrastructure

The project includes comprehensive QEMU-based testing infrastructure for end-to-end validation of USB/IP protocol implementation.

### QEMU Test Components
- **QEMUTestServer**: Test server executable for protocol validation
- **Scripts/qemu/**: QEMU testing infrastructure and utilities
- **Tests/QEMUIntegrationTests/**: Integration tests for QEMU workflows

### QEMU Test Execution
```bash
# QEMU test orchestration (main entry point)
./Scripts/qemu/test-orchestrator.sh <scenario>

# Available test scenarios:
./Scripts/qemu/test-orchestrator.sh basic      # Basic connectivity testing
./Scripts/qemu/test-orchestrator.sh protocol  # USB/IP protocol validation  
./Scripts/qemu/test-orchestrator.sh stress    # Load testing (production only)
./Scripts/qemu/test-orchestrator.sh full      # Complete test suite

# Environment-specific QEMU testing
TEST_ENVIRONMENT=development ./Scripts/qemu/test-orchestrator.sh basic
TEST_ENVIRONMENT=ci ./Scripts/qemu/test-orchestrator.sh protocol
TEST_ENVIRONMENT=production ./Scripts/qemu/test-orchestrator.sh full

# QEMU test configuration and status
./Scripts/qemu/test-orchestrator.sh --info           # Show environment config
./Scripts/qemu/test-orchestrator.sh --dry-run full   # Preview test execution
```

### QEMU Environment Management
```bash
# Environment validation and setup
./Scripts/qemu/validate-environment.sh               # Check QEMU prerequisites
./Scripts/qemu/validate-environment.sh install-help  # Installation guidance

# VM lifecycle management
./Scripts/qemu/vm-manager.sh create test-vm         # Create VM
./Scripts/qemu/vm-manager.sh start test-vm          # Start VM
./Scripts/qemu/vm-manager.sh stop test-vm           # Stop VM
./Scripts/qemu/vm-manager.sh status test-vm         # Check VM status

# QEMU test maintenance
./Scripts/qemu/cleanup.sh status                    # Show environment status
./Scripts/qemu/cleanup.sh full                      # Complete cleanup
./Scripts/qemu/cleanup.sh processes                 # Clean up processes only
./Scripts/qemu/cleanup.sh files --max-age 3         # Clean files older than 3 days
```

### Integration with Test Scripts
QEMU testing is integrated with the main test execution scripts:

```bash
# Development tests with QEMU (optional)
swift test --parallel

# CI tests with QEMU mocking
swift test --parallel

# Production tests with full QEMU integration
swift test --parallel   # Automatically includes QEMU tests
```

### QEMU Test Configuration

Environment variables for QEMU testing:
- `QEMU_TEST_MODE`: Set to `mock` or `vm` (default: auto-detect)
- `QEMU_TIMEOUT`: Test timeout in seconds (environment-specific default)
- `ENABLE_QEMU_TESTS`: Enable QEMU tests in development environment
- `QEMU_VM_MEMORY`: VM memory allocation (e.g., 512M)
- `QEMU_CPU_CORES`: VM CPU core count (e.g., 2)

### QEMU Test Reporting
```bash
# Generate QEMU test reports
./Scripts/qemu/test-orchestrator.sh --report-only

# Integration with main test reporting
swift test --parallel   # Includes QEMU results
```

## Release Automation

The project includes comprehensive automated release workflows with GitHub Actions integration, artifact building, code signing, and distribution management.

### Release Workflow Overview

The release system uses a multi-stage automated pipeline:

1. **Release Preparation** (`Scripts/prepare-release.sh`)
2. **GitHub Actions Workflows** (`.github/workflows/`)
4. **Rollback Utilities** (`Scripts/rollback-release.sh`)
5. **Monitoring and Alerting** (Automated workflow monitoring)

### Release Preparation

Use the release preparation script to validate and prepare releases locally:

```bash
# Prepare a release (validates environment, runs tests, creates tags)
./Scripts/prepare-release.sh v1.2.3

# Dry run to preview release preparation
./Scripts/prepare-release.sh --dry-run v1.2.3

# Prepare release with custom options
./Scripts/prepare-release.sh --skip-tests --force v1.2.3-beta

# Emergency release preparation (skips validation)
./Scripts/prepare-release.sh --force --skip-tests --skip-lint v1.2.4
```

### GitHub Actions Workflows (Consolidated Architecture)

The project uses a streamlined GitHub Actions architecture with three consolidated workflows:

#### CI (Consolidated) Workflow (`.github/workflows/ci.yml`)
- **Purpose**: Main continuous integration validation for all code changes
- **Triggers**: Push to main, pull requests, workflow calls from release workflows, manual dispatch
- **Jobs**: Code quality (SwiftLint), build validation, comprehensive test suite, release validation (conditional)
- **Features**: Parallel execution, environment-specific testing, reusable composite actions
- **Duration**: ~5-8 minutes for typical CI run

```bash
# Manual CI trigger with options
gh workflow run ci.yml -f test_environment=ci -f enable_qemu_tests=false

# Manual CI trigger for production testing
gh workflow run ci.yml -f test_environment=production -f enable_qemu_tests=true

# Manual release validation mode
gh workflow run ci.yml -f release_validation=true -f test_environment=ci
```

#### Production Release (Streamlined) Workflow (`.github/workflows/release.yml`)
- **Purpose**: Automated release process from validation to publication
- **Triggers**: Git tags (`v*`) or manual dispatch
- **Jobs**: Release validation, CI validation (via workflow_call), artifact building, release creation, post-release validation
- **Features**: Reuses CI workflow for validation, code signing, multi-architecture builds, GitHub release creation
- **Duration**: ~15-20 minutes for full release

```bash
# Manual release trigger (via GitHub web interface or gh CLI)
gh workflow run release.yml -f version=v1.2.3 -f prerelease=false

# Emergency release (skips CI validation)
gh workflow run release.yml -f version=v1.2.3-hotfix -f skip_tests=true
```

#### Security Scanning Workflow (`.github/workflows/security.yml`)
- **Purpose**: Comprehensive security monitoring without blocking development
- **Triggers**: Daily schedule (6 AM UTC), push/PR on security-relevant files, manual dispatch
- **Jobs**: Dependency vulnerability scanning, static security analysis, security summary
- **Features**: Configurable scan types and severity thresholds, detailed security reporting
- **Duration**: ~3-5 minutes for comprehensive scan

```bash
# Manual security scan with options
gh workflow run security.yml -f scan_type=comprehensive -f severity_threshold=high

# Quick dependency-only scan
gh workflow run security.yml -f scan_type=dependency-only -f severity_threshold=critical
```

#### Composite Actions (`.github/actions/`)
Reusable workflow components that eliminate duplication:

- **setup-swift-environment**: Swift environment setup with caching, SwiftLint installation, dependency resolution
- **swiftlint-validation**: Standardized code quality validation with configurable options  
- **run-test-suite**: Parameterized test execution across different environments

**Benefits of Consolidated Architecture**:
- Reduced workflow maintenance (7 workflows → 3 workflows)
- Eliminated duplication through composite actions
- Consistent environment setup and validation
- Improved caching and performance
- Enhanced reusability through workflow_call interface

### Homebrew Formula Distribution

The project uses a repository dispatch pattern to automatically update the Homebrew tap repository when new releases are published.

The formula in the tap is `Formula/usbip.rb` (class `Usbip`, installed with `brew install usbip`) — not `usbipd-mac.rb`. Several documents under `Documentation/` still use the wrong filename; the tap's own scripts are the authority.

#### Repository Dispatch Workflow

The main repository (`usbipd-mac`) triggers updates to the tap repository (`homebrew-usbipd-mac`) using GitHub's repository dispatch events:

1. **Release Workflow Trigger**: When a new release is created, the release workflow sends a `repository_dispatch` event
2. **Tap Repository Response**: The tap repository receives the event and updates the formula file
3. **Automated Validation**: Binary download, checksum verification, and formula syntax validation
4. **Error Handling**: Automatic issue creation for failed updates with detailed diagnostics

```bash
# Manual repository dispatch trigger (for testing)
gh api repos/beriberikix/homebrew-usbipd-mac/dispatches \
  --method POST \
  --field event_type=formula_update \
  --field client_payload='{"version":"v1.2.3","binary_url":"https://github.com/beriberikix/usbipd-mac/releases/download/v1.2.3/usbipd-v1.2.3-macos","sha256":"abc123..."}'

# Test repository dispatch workflow validation
cd ~/path/to/homebrew-usbipd-mac
./Scripts/test-formula-update.sh
```

#### Formula Update Process

The tap repository workflow (`homebrew-usbipd-mac/.github/workflows/formula-update.yml`) handles the following steps:

1. **Payload Validation**: Verify required fields (version, binary_url, sha256)
2. **Binary Download**: Download and validate the binary against expected checksum
3. **Formula Update**: Update version, URL, and SHA256 in the formula file
4. **Syntax Validation**: Ensure Ruby syntax is correct using `ruby -c`
5. **Atomic Operations**: Rollback on failure to maintain repository integrity

#### Emergency Procedures for Homebrew Updates

In case of automated update failures:

```bash
# Manual formula update (emergency procedure)
cd ~/path/to/homebrew-usbipd-mac
./Scripts/manual-update.sh v1.2.3 https://github.com/beriberikix/usbipd-mac/releases/download/v1.2.3/usbipd-v1.2.3-macos abc123...

# Force update with validation bypass (emergency only)
./Scripts/manual-update.sh --force --skip-validation v1.2.3-hotfix

# Check update status and logs
gh run list --repo beriberikix/homebrew-usbipd-mac
gh run view --repo beriberikix/homebrew-usbipd-mac [run-id]
```

#### Troubleshooting Formula Updates

Common issues and solutions:

1. **Repository Dispatch Failures**:
   - Verify `HOMEBREW_TAP_DISPATCH_TOKEN` secret is configured
   - Check token permissions (requires `repository` scope)
   - Validate payload structure and required fields

2. **Binary Download Issues**:
   - Confirm binary is accessible at the provided URL
   - Verify SHA256 checksum matches the expected value
   - Check network connectivity and GitHub release availability

3. **Formula Syntax Errors**:
   - Review Ruby syntax using `ruby -c Formula/usbip.rb`
   - Check for proper escaping of special characters
   - Validate version format and URL structure

4. **Rollback Scenarios**:
   - Repository automatically rolls back to previous formula on failure
   - Manual rollback: `git checkout HEAD~1 -- Formula/usbip.rb`
   - Issue creation provides detailed failure context for investigation

#### Testing and Validation Scripts

Available testing utilities in the tap repository:

```bash
# Validate tap repository workflow
./Scripts/test-formula-update.sh

# Test binary validation process
./Scripts/validate-binary.sh [binary_url] [expected_sha256]

# Test formula update with mock data
./Scripts/update-formula-from-dispatch.sh # Uses GITHUB_EVENT_PATH

# Create test issue (dry run)
DRY_RUN=true ./Scripts/create-update-issue.sh "Test error" "validation" "v1.2.3" "Test details"
```

### Release Artifact Management

#### Artifact Validation
Validate release artifacts for integrity, signatures, and compatibility:

```bash
# Validate all release artifacts

# Validate specific version artifacts

# Skip signature validation (development/testing)

# Comprehensive validation with verbose output
```

#### Release Rollback and Recovery
Handle failed releases and cleanup incomplete artifacts:

```bash
# Rollback failed release (removes tags, cleans artifacts)
./Scripts/rollback-release.sh v1.2.3

# Rollback with different strategies
./Scripts/rollback-release.sh --type failed-release v1.2.3      # Full Git rollback
./Scripts/rollback-release.sh --type incomplete-build          # Build artifacts only
./Scripts/rollback-release.sh --type artifacts-only            # Preserve Git state

# Cleanup old artifacts and temporary files
./Scripts/rollback-release.sh --cleanup-only --max-age 30

# Preview rollback actions without changes
./Scripts/rollback-release.sh --dry-run v1.2.3
```

### Release Testing and Validation

Release behaviour is validated by running the workflows themselves, not by asserting on
them from XCTest. `Tests/Integration/`, `Tests/ReleaseWorkflowTests/`,
`Tests/ReleaseValidation/` and `Tests/Distribution/` previously held ~8,300 lines of
Swift that inspected YAML, shell scripts and `brew` output through the `act` framework.
They were compiled by no target, had never run, and were removed in 2026-08.

### Release Security and Code Signing

The release system includes comprehensive code signing and security validation:

#### Code Signing Setup
Configure Apple Developer certificates and GitHub Secrets:

- `DEVELOPER_ID_CERTIFICATE`: Base64-encoded Developer ID Application certificate
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`: Certificate password
- `NOTARIZATION_USERNAME`: Apple ID for notarization
- `NOTARIZATION_PASSWORD`: App-specific password for notarization

#### Security Scanning
Automated security scanning is integrated into release workflows:

- Dependency vulnerability scanning
- Code signature validation
- Binary security analysis
- Supply chain verification

### Release Performance and Monitoring

#### Performance Benchmarking
Monitor release workflow performance and identify optimization opportunities:

```bash
# Benchmark release workflow performance

# Generate performance optimization report
```

#### Release Metrics and Monitoring
Track release success rates, performance metrics, and infrastructure health:

- **Success Rate Monitoring**: Track release success/failure rates over time
- **Performance Metrics**: Build times, test execution duration, artifact sizes
- **Infrastructure Health**: Workflow availability, dependency status, environment validation

### Emergency Release Procedures

For emergency releases or hotfixes:

1. **Immediate Release**: Use force flags to bypass non-critical validation
2. **Hotfix Process**: Create hotfix branches with accelerated testing
3. **Rollback Strategy**: Automated rollback with preserved backup capabilities
4. **Recovery Procedures**: Comprehensive cleanup and state restoration

```bash
# Emergency release preparation
./Scripts/prepare-release.sh --force --skip-lint v1.2.4-hotfix

# Emergency GitHub Actions trigger
gh workflow run release.yml -f version=v1.2.4-hotfix -f skip_tests=true

# Emergency rollback if needed
./Scripts/rollback-release.sh --type failed-release v1.2.4-hotfix
```

### Release Troubleshooting

#### Common Issues and Solutions

1. **Build Failures**: Check SwiftLint compliance, dependency resolution, environment setup
2. **Test Failures**: Validate test environment, check QEMU integration, review test logs
3. **Code Signing Issues**: Verify certificate validity, check secret configuration, validate entitlements
4. **Artifact Problems**: Run artifact validation, check checksums, verify file permissions
5. **Workflow Failures**: Review GitHub Actions logs, check secret access, validate branch protection

#### Diagnostic Commands

```bash
# Comprehensive release health check
./Scripts/release-health-check.sh

# Validate release environment
./Scripts/validate-release-environment.sh

# Generate release troubleshooting report
./Scripts/generate-release-diagnostics.sh --verbose
```

### AI Assistant Context for Release Management

When working with release automation:

1. **Always validate environment** before making release-related changes
2. **Run comprehensive tests** before triggering release workflows  
3. **Use dry-run mode** to preview changes before execution
4. **Monitor workflow execution** and be prepared to rollback if issues occur
5. **Follow security best practices** for code signing and artifact handling
6. **Document any manual interventions** and update automation accordingly

The release automation system is designed for reliability, security, and minimal manual intervention while providing comprehensive monitoring and rollback capabilities for production deployments.