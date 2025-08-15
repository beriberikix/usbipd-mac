# CI Workflows Documentation

This document provides comprehensive documentation for the consolidated GitHub Actions CI/CD workflows in the usbipd-mac project.

## Overview

The usbipd-mac project uses a streamlined CI/CD architecture with three primary workflows that have been consolidated from seven previous workflows. This consolidation reduces duplication, improves maintainability, and provides consistent validation across all stages of development and release.

## Workflow Architecture

### Consolidated Workflow System

The project uses three main workflows:

1. **CI (Consolidated)** (`.github/workflows/ci.yml`) - Main continuous integration workflow
2. **Production Release (Streamlined)** (`.github/workflows/release.yml`) - Release automation workflow
3. **Security Scanning** (`.github/workflows/security.yml`) - Dedicated security analysis workflow

### Supporting Components

**Composite Actions** (`.github/actions/`) provide reusable functionality:
- `setup-swift-environment` - Swift environment setup with caching
- `swiftlint-validation` - Code quality validation
- `run-test-suite` - Parameterized test execution

## Detailed Workflow Documentation

### 1. CI (Consolidated) Workflow

**File**: `.github/workflows/ci.yml`

**Purpose**: Provides comprehensive continuous integration validation for all code changes.

#### Triggers

- **Push to main branch** (excludes documentation files)
- **Pull requests to main branch** (excludes documentation files)
- **Workflow call** (enables reuse by release workflows)
- **Manual dispatch** (with configurable options)

#### Jobs

##### Code Quality Job
- **Purpose**: Validates Swift code against project style guidelines
- **Uses**: `swiftlint-validation` composite action
- **Features**: Strict mode validation, caching, detailed reporting
- **Output**: Validation result and violation count

##### Build Validation Job
- **Purpose**: Ensures project compiles successfully
- **Uses**: `setup-swift-environment` composite action
- **Features**: Verbose output, dependency resolution, compilation verification
- **Output**: Swift version and cache status

##### Test Suite Job
- **Purpose**: Executes comprehensive test suite
- **Uses**: `run-test-suite` composite action
- **Features**: Environment-specific testing (development/ci/production), parallel execution, optional QEMU and hardware tests
- **Configuration**: Matrix strategy for different test environments
- **Output**: Test results, execution time, test count, environment capabilities

##### Release Validation Job (Conditional)
- **Purpose**: Performs release-specific validation when triggered by tags or release inputs
- **Features**: Artifact validation, version format validation, release readiness checks
- **Conditions**: Only runs when `IS_RELEASE_VALIDATION` is true

##### CI Summary Job
- **Purpose**: Aggregates all job results and determines overall CI status
- **Features**: Comprehensive status analysis, release readiness determination
- **Output**: Overall success status and release readiness

#### Workflow Call Interface

The CI workflow can be called by other workflows with these inputs:

```yaml
inputs:
  release_validation:        # Enable release-specific validation
    type: boolean
    default: false
  skip_optional_tests:       # Skip optional tests for faster validation
    type: boolean  
    default: false
  test_environment:          # Test environment (development/ci/production)
    type: string
    default: 'ci'
```

#### Manual Dispatch Options

```yaml
inputs:
  test_environment:          # Test environment choice
    type: choice
    options: [development, ci, production]
  enable_qemu_tests:         # Enable QEMU integration tests
    type: boolean
  enable_hardware_tests:     # Enable hardware-dependent tests
    type: boolean
  release_validation:        # Enable release validation
    type: boolean
```

### 2. Production Release (Streamlined) Workflow

**File**: `.github/workflows/release.yml`

**Purpose**: Automates the complete release process from validation to GitHub release publication.

#### Triggers

- **Push to version tags** (`v*`)
- **Manual dispatch** with version specification

#### Jobs

##### Release Validation Job
- **Purpose**: Validates release triggers and extracts version metadata
- **Features**: Semantic versioning validation, pre-release detection, release type identification
- **Output**: Version, pre-release status, release type

##### CI Validation Job
- **Purpose**: Reuses consolidated CI workflow for complete validation
- **Uses**: `workflow_call` to invoke `ci.yml` with release-specific parameters
- **Configuration**: Release validation enabled, comprehensive testing

##### Build Artifacts Job
- **Purpose**: Creates production-ready release artifacts
- **Features**: Multi-architecture builds (arm64/x86_64), code signing, artifact packaging
- **Requirements**: Apple Developer certificates for code signing
- **Output**: Binary artifacts, checksums, packaged archives

##### Create Release Job
- **Purpose**: Creates GitHub release with artifacts
- **Features**: Automatic release notes generation, artifact upload, proper tagging
- **Output**: Published GitHub release with downloadable artifacts

##### Post-Release Validation Job
- **Purpose**: Validates published release and provides completion summary
- **Features**: Release accessibility verification, comprehensive status reporting

#### Code Signing Configuration

The release workflow supports Apple Developer ID code signing:

```yaml
env:
  DEVELOPER_ID_CERTIFICATE: ${{ secrets.DEVELOPER_ID_CERTIFICATE }}
  DEVELOPER_ID_CERTIFICATE_PASSWORD: ${{ secrets.DEVELOPER_ID_CERTIFICATE_PASSWORD }}
  NOTARIZATION_USERNAME: ${{ secrets.NOTARIZATION_USERNAME }}
  NOTARIZATION_PASSWORD: ${{ secrets.NOTARIZATION_PASSWORD }}
```

#### Manual Release Options

```yaml
inputs:
  version:          # Release version (e.g., v1.2.3)
    required: true
  prerelease:       # Mark as pre-release
    type: boolean
    default: false
  skip_tests:       # Skip test validation (emergency use only)
    type: boolean
    default: false
```

### 3. Security Scanning Workflow

**File**: `.github/workflows/security.yml`

**Purpose**: Provides comprehensive security monitoring without blocking development workflows.

#### Triggers

- **Scheduled execution** (daily at 6 AM UTC)
- **Push to main** (when security-relevant files change)
- **Pull requests** (when security-relevant files change)
- **Manual dispatch** with scan configuration options

#### Jobs

##### Dependency Vulnerability Scanning Job
- **Purpose**: Analyzes Swift package dependencies for known vulnerabilities
- **Features**: Package.resolved analysis, vulnerability database checking, severity assessment
- **Output**: Vulnerability count, critical vulnerability count, scan status

##### Static Security Analysis
- **Purpose**: Scans source code for hardcoded secrets and security anti-patterns
- **Features**: Secret pattern detection, security anti-pattern identification, false positive filtering
- **Patterns**: API keys, private keys, GitHub tokens, AWS credentials, unsafe Swift operations

##### Security Summary Job
- **Purpose**: Aggregates security scan results and determines overall security status
- **Features**: Comprehensive security status reporting, threshold-based failure

#### Manual Scan Options

```yaml
inputs:
  scan_type:                # Type of scan (quick/comprehensive/dependency-only)
    type: choice
    default: 'comprehensive'
  severity_threshold:       # Minimum severity to fail on (low/moderate/high/critical)
    type: choice
    default: 'high'
```

## Composite Actions

### setup-swift-environment

**Purpose**: Standardizes Swift development environment setup across all workflows.

**Inputs**:
- `cache-key-suffix`: Cache key variation for different contexts
- `install-swiftlint`: Whether to install SwiftLint
- `setup-test-scripts`: Whether to make test scripts executable
- `validate-environment`: Whether to validate test environment

**Features**:
- Swift environment detection and reporting
- SwiftLint installation with caching
- Swift package dependency caching
- Test script permission setup
- Optional environment validation

**Outputs**:
- `swift-version`: Detected Swift version
- `swiftlint-version`: Installed SwiftLint version
- `cache-hit`: Whether package cache was hit

### swiftlint-validation

**Purpose**: Provides standardized code quality validation across workflows.

**Features**:
- Configurable strict mode validation
- Comprehensive caching strategy
- Multiple reporter format support
- Detailed violation reporting

### run-test-suite

**Purpose**: Enables flexible, parameterized test execution across different environments.

**Features**:
- Environment-specific test execution (development/ci/production)
- Configurable test capabilities (QEMU, hardware, system extension)
- Parallel execution support
- Comprehensive timeout management
- Detailed result reporting

## Migration Benefits

### From Seven to Three Workflows

**Previous workflows** (now consolidated):
- `ci.yml` (replaced by consolidated CI)
- `pre-release.yml` (functionality integrated into CI and release)
- `release.yml` (replaced by streamlined release)
- `release-monitoring.yml` (monitoring integrated into release)
- `release-optimization.yml` (optimizations integrated into release)
- `security-scanning.yml` (replaced by dedicated security workflow)
- `validate-branch-protection.yml` (validation integrated into CI)

**Benefits achieved**:
- **Reduced Duplication**: Composite actions eliminate repeated configuration
- **Improved Maintainability**: Centralized logic easier to update and debug
- **Consistent Validation**: Same environment setup and validation across all contexts
- **Enhanced Performance**: Optimized caching and parallelization
- **Better Reusability**: Workflow call interface enables code reuse
- **Simplified Debugging**: Fewer workflows to troubleshoot and monitor

## Usage Patterns

### Development Workflow

1. **Code changes** trigger CI workflow on pull requests
2. **Code quality**, **build validation**, and **test suite** jobs run in parallel
3. **Results aggregated** in CI summary job
4. **Pull request status** updated with validation results

### Release Workflow

1. **Tag creation** or **manual dispatch** triggers release workflow
2. **Release validation** extracts and validates version information
3. **CI validation** calls consolidated CI workflow for comprehensive validation
4. **Artifact building** creates signed, production-ready binaries
5. **GitHub release** published with artifacts and generated release notes
6. **Post-release validation** ensures release accessibility

### Security Monitoring

1. **Daily scheduled scans** run security analysis
2. **Code changes** trigger targeted security scans
3. **Dependency vulnerabilities** and **static analysis** run in parallel
4. **Results aggregated** with configurable severity thresholds
5. **Artifacts uploaded** for detailed security reporting

## Troubleshooting Guide

### Common Issues

#### CI Workflow Failures

**Code Quality Failures**:
- Check SwiftLint output for specific violations
- Review `.swiftlint.yml` configuration
- Run `swiftlint --fix` locally to auto-fix violations

**Build Failures**:
- Verify Swift version compatibility
- Check dependency resolution in Package.swift
- Review build logs for compilation errors

**Test Failures**:
- Check test environment compatibility
- Verify QEMU integration if enabled
- Review test logs for specific failure details

#### Release Workflow Failures

**Version Validation Failures**:
- Ensure version follows semantic versioning (vX.Y.Z)
- Check tag format and naming convention
- Verify pre-release suffix format

**Code Signing Failures**:
- Verify Apple Developer certificates are properly configured
- Check certificate validity and permissions
- Ensure notarization credentials are correct

**Artifact Building Failures**:
- Check Swift build configuration
- Verify multi-architecture support
- Review artifact packaging logic

#### Security Workflow Failures

**Dependency Scanning Issues**:
- Verify Package.resolved format
- Check dependency parsing logic
- Review vulnerability database connectivity

**Static Analysis Issues**:
- Check secret pattern accuracy
- Review false positive filtering
- Verify source file accessibility

### Debugging Commands

```bash
# Local CI validation
swiftlint lint --strict                          # Code quality check
swift build --verbose                            # Build validation
./Scripts/run-ci-tests.sh                        # CI test execution

# Local release preparation
./Scripts/prepare-release.sh --dry-run v1.2.3    # Release preparation
swift build --configuration release              # Release build

# Local security analysis
find Sources -name "*.swift" -exec grep -l "secret\|password\|key" {} + # Secret detection
```

### Environment Variables

**CI Workflow**:
- `GITHUB_TOKEN`: GitHub API access
- `IS_RELEASE_VALIDATION`: Release validation mode
- `SKIP_OPTIONAL_TESTS`: Optional test control
- `TEST_ENVIRONMENT`: Test environment selection

**Release Workflow**:
- `DEVELOPER_ID_CERTIFICATE`: Code signing certificate
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`: Certificate password
- `NOTARIZATION_USERNAME`: Apple ID for notarization
- `NOTARIZATION_PASSWORD`: App-specific password

**Security Workflow**:
- `SCAN_TYPE`: Security scan type configuration
- `SEVERITY_THRESHOLD`: Failure threshold configuration

## Monitoring and Metrics

### Key Metrics

- **CI Success Rate**: Percentage of successful CI runs
- **Build Performance**: Average build and test execution times
- **Cache Hit Rate**: Swift package and SwiftLint cache effectiveness
- **Release Success Rate**: Percentage of successful releases
- **Security Issue Detection**: Count and severity of detected issues

### Status Monitoring

- **GitHub Actions dashboard**: Real-time workflow status
- **Branch protection rules**: CI requirement enforcement
- **Release notifications**: Automated release announcements
- **Security alerts**: Critical vulnerability notifications

## Future Enhancements

### Planned Improvements

- **Enhanced caching strategies** for improved performance
- **Parallel test execution** across multiple environments
- **Advanced security scanning** with additional vulnerability databases
- **Automated dependency updates** with security validation
- **Performance benchmarking** integration
- **Deployment automation** for different environments

### Extensibility

The consolidated workflow architecture is designed for easy extension:

- **Additional composite actions** for specialized functionality
- **New test environments** through matrix strategy expansion
- **Enhanced security scanning** through additional jobs
- **Custom validation steps** through workflow call interface
- **Integration with external tools** through action marketplace

This documentation provides a complete reference for understanding, using, and maintaining the consolidated CI/CD workflows in the usbipd-mac project.