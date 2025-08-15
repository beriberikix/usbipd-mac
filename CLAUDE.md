# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

usbipd-mac is a macOS USB/IP protocol implementation for sharing USB devices over IP networks. The project is built using Swift Package Manager and targets macOS 11+.

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

The project uses an environment-based testing strategy with three distinct test environments:

- **DevelopmentTests**: Fast unit tests with comprehensive mocking (<1 minute execution)
- **CITests**: Automated tests without hardware dependencies (CI-compatible, <3 minutes)
- **ProductionTests**: Comprehensive validation with QEMU and hardware integration (<10 minutes)

Shared infrastructure:
- **Tests/SharedUtilities/**: Common test fixtures, assertion helpers, and environment configuration
- **Tests/TestMocks/**: Environment-specific mock implementations

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

#### Environment-Specific Testing
```bash
# Development environment (fast feedback, <1 min)
./Scripts/run-development-tests.sh

# CI environment (automated testing, <3 min)
./Scripts/run-ci-tests.sh

# Production environment (comprehensive validation, <10 min)
./Scripts/run-production-tests.sh
```

#### Traditional Testing Commands
```bash
# Run all tests
swift test --parallel --verbose

# Run specific test environment
swift test --filter DevelopmentTests
swift test --filter CITests
swift test --filter ProductionTests

# Test environment validation
./Scripts/test-environment-setup.sh validate
```

### Code Quality
```bash
# Run SwiftLint (strict mode like CI)
swiftlint lint --strict

# Auto-fix violations
swiftlint --fix
```

### Full CI Validation Locally
```bash
# Complete validation sequence (matches CI pipeline)
swiftlint lint --strict
swift build --verbose
./Scripts/run-ci-tests.sh

# Full production validation for release preparation
swiftlint lint --strict
swift build --verbose
./Scripts/run-production-tests.sh
./Scripts/generate-test-report.sh
```

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
- `run-development-tests.sh`: Fast development test execution
- `run-ci-tests.sh`: CI-compatible automated testing
- `run-production-tests.sh`: Comprehensive production validation

### Test Infrastructure Scripts
- `qemu-test-validation.sh`: QEMU server validation utilities
- `test-environment-setup.sh`: Environment detection and setup
- `generate-test-report.sh`: Unified test execution reporting

### Usage Examples
```bash
# Quick development feedback
./Scripts/run-development-tests.sh

# Validate environment before testing
./Scripts/test-environment-setup.sh validate

# Generate comprehensive test report
./Scripts/generate-test-report.sh --environment production
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
ENABLE_QEMU_TESTS=true ./Scripts/run-development-tests.sh

# CI tests with QEMU mocking
QEMU_TEST_MODE=mock ./Scripts/run-ci-tests.sh

# Production tests with full QEMU integration
./Scripts/run-production-tests.sh  # Automatically includes QEMU tests
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
./Scripts/generate-test-report.sh --environment production  # Includes QEMU results
```

## Release Automation

The project includes comprehensive automated release workflows with GitHub Actions integration, artifact building, code signing, and distribution management.

### Release Workflow Overview

The release system uses a multi-stage automated pipeline:

1. **Release Preparation** (`Scripts/prepare-release.sh`)
2. **GitHub Actions Workflows** (`.github/workflows/`)
3. **Artifact Validation** (`Scripts/validate-release-artifacts.sh`)
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

### GitHub Actions Workflows

The automated release system includes several GitHub Actions workflows:

#### Production Release Workflow (`.github/workflows/release.yml`)
- **Triggers**: Git tags (`v*`) or manual dispatch
- **Stages**: Validation → Build → Test → Artifact Creation → Release Publication
- **Features**: Code signing, notarization, artifact validation, multi-architecture builds
- **Duration**: ~15-20 minutes for full release

```bash
# Manual release trigger (via GitHub web interface or gh CLI)
gh workflow run release.yml -f version=v1.2.3 -f prerelease=false

# Emergency release (skips some tests)
gh workflow run release.yml -f version=v1.2.3 -f skip_tests=true
```

#### Pre-Release Validation Workflow (`.github/workflows/pre-release.yml`)
- **Triggers**: Pull requests to main or manual dispatch
- **Validation Levels**: Quick (PR) → Comprehensive (manual) → Release Candidate (pre-release)
- **Features**: Multi-level testing, release readiness validation

```bash
# Run comprehensive pre-release validation
gh workflow run pre-release.yml -f validation_level=comprehensive

# Full release candidate validation
gh workflow run pre-release.yml -f validation_level=release-candidate
```

#### Release Monitoring Workflow (`.github/workflows/release-monitoring.yml`)
- **Purpose**: Monitor release workflow execution, failure alerts, metrics collection
- **Triggers**: Automatic (on workflow completion) or manual dispatch
- **Features**: Failure notifications, performance metrics, health checks

```bash
# Manual monitoring and status check
gh workflow run release-monitoring.yml -f monitoring_mode=status

# Generate release metrics report
gh workflow run release-monitoring.yml -f monitoring_mode=metrics -f time_window=24

# Perform health check on release infrastructure
gh workflow run release-monitoring.yml -f monitoring_mode=health-check
```

### Release Artifact Management

#### Artifact Validation
Validate release artifacts for integrity, signatures, and compatibility:

```bash
# Validate all release artifacts
./Scripts/validate-release-artifacts.sh --artifacts-path ./release-artifacts

# Validate specific version artifacts
./Scripts/validate-release-artifacts.sh --expected-version v1.2.3

# Skip signature validation (development/testing)
./Scripts/validate-release-artifacts.sh --skip-signature-check

# Comprehensive validation with verbose output
./Scripts/validate-release-artifacts.sh --verbose
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

#### End-to-End Release Testing
The project includes comprehensive end-to-end release testing (`Tests/Integration/ReleaseEndToEndTests.swift`):

- **Phase 1**: Source code readiness validation
- **Phase 2**: Build system validation  
- **Phase 3**: Artifact generation testing
- **Phase 4**: Code signing validation
- **Phase 5**: Artifact integrity verification
- **Phase 6**: Distribution simulation
- **Phase 7**: QEMU integration testing
- **Phase 8**: Rollback capability testing

```bash
# Run end-to-end release tests
swift test --filter ReleaseEndToEndTests

# Run with specific environment
TEST_ENVIRONMENT=production swift test --filter ReleaseEndToEndTests
```

#### Release Workflow Testing
Validate GitHub Actions workflows locally using act framework (`Tests/ReleaseWorkflowTests/`):

```bash
# Test release workflows (requires act installation)
swift test --filter ReleaseWorkflowTests

# Generate workflow validation report
./Scripts/generate-workflow-test-report.sh
```

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
./Scripts/benchmark-release-performance.sh

# Generate performance optimization report
./Scripts/benchmark-release-performance.sh --generate-report
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