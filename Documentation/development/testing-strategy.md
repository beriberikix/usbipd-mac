# Testing Strategy

This document outlines the comprehensive testing strategy for usbipd-mac, covering unit tests, integration tests, System Extension testing, and continuous integration validation.

## Overview

The testing strategy is designed to ensure reliability and functionality across all components while accommodating the unique requirements of System Extension development on macOS. Testing is performed at multiple levels with different environments and validation approaches.

## Test Suite Structure

### Core Test Suites

#### Unit Tests
```bash
# Run all tests using Swift Package Manager
swift test

# Run tests using Xcode
xcodebuild -scheme usbipd-mac test

# Run specific test suites
swift test --filter USBIPDCoreTests          # Core functionality tests
swift test --filter USBIPDCLITests           # CLI interface tests
swift test --filter SystemExtensionTests     # System Extension tests
swift test --filter IntegrationTests         # Integration tests
```

#### Environment-Based Testing

The project uses a three-tier environment-based testing approach:

- **DevelopmentTests**: Fast unit tests with comprehensive mocking (<1 minute execution)
- **CITests**: Automated tests without hardware dependencies (CI-compatible, <3 minutes)
- **ProductionTests**: Comprehensive validation with QEMU and hardware integration (<10 minutes)

### Environment-Specific Test Execution

#### Development Environment Testing
```bash
# Development environment (fast feedback, <1 min)
./Scripts/run-development-tests.sh
```
- **Purpose**: Rapid feedback during active development
- **Execution time**: <1 minute
- **Coverage**: Unit tests with comprehensive mocking
- **Use case**: Local development, IDE integration

#### CI Environment Testing
```bash
# CI environment (automated testing, <3 min)
./Scripts/run-ci-tests.sh
```
- **Purpose**: Automated validation in GitHub Actions
- **Execution time**: <3 minutes
- **Coverage**: Protocol and network tests without hardware dependencies
- **Use case**: Pull request validation, automated testing

#### Production Environment Testing
```bash
# Production environment (comprehensive validation, <10 min)
./Scripts/run-production-tests.sh
```
- **Purpose**: Complete validation for release preparation
- **Execution time**: <10 minutes
- **Coverage**: QEMU integration, hardware validation, System Extension testing
- **Use case**: Release candidate validation, comprehensive testing

### Traditional Testing Commands

#### Basic Test Execution
```bash
# Run all tests with parallel execution
swift test --parallel --verbose

# Run specific test environment
swift test --filter DevelopmentTests
swift test --filter CITests
swift test --filter ProductionTests

# Test environment validation
./Scripts/test-environment-setup.sh validate
```

## System Extension Testing Strategy

Testing System Extension functionality requires special setup and considerations due to macOS security requirements.

### Setup Requirements

```bash
# Enable development mode for testing
sudo systemextensionsctl developer on

# Enable System Extension development mode
sudo systemextensionsctl developer on

# Build and install for development
swift build
sudo usbipd daemon --install-extension

# Verify installation
usbipd status
systemextensionsctl list
```

### System Extension Test Types

#### Installation and Activation Tests
```bash
# Run System Extension integration tests
swift test --filter SystemExtensionInstallationTests

# Test bundle creation and validation
swift test --filter BuildOutputVerificationTests
```

#### Runtime Testing
```bash
# Manual System Extension testing
usbipd status                    # Check System Extension status
usbipd status --detailed         # Detailed health information
usbipd status --health           # Health check only

# Test System Extension functionality (requires development mode)
swift test --filter IntegrationTests --verbose
```

## QEMU Testing Strategy

### QEMU Test Server Validation

The project includes a lightweight QEMU test server for end-to-end protocol validation:

```bash
# Run QEMU test server validation
./Scripts/qemu-test-validation.sh

# Build QEMU test server
swift build --product QEMUTestServer

# Run QEMU validation script
./Scripts/qemu-test-validation.sh

# Run integration tests specifically
swift test --filter IntegrationTests --verbose
```

### Integration Test Coverage

- **Network communication**: TCP server and client connection handling
- **Protocol flow testing**: USB/IP message encoding/decoding validation
- **End-to-end scenarios**: Complete device sharing workflows

## Test Infrastructure

### Shared Testing Utilities

Located in `Tests/SharedUtilities/`:
- Common test fixtures
- Assertion helpers
- Environment configuration
- Mock implementations for different test environments

### Environment-Specific Mocks

Located in `Tests/TestMocks/`:
- Environment-specific mock libraries for reliable testing
- Conditional hardware detection and graceful degradation
- Comprehensive test reporting and environment validation

### Test Execution Scripts

Located in `Scripts/` directory:

#### Test Execution Scripts
- `run-development-tests.sh`: Fast development test execution
- `run-ci-tests.sh`: CI-compatible automated testing
- `run-production-tests.sh`: Comprehensive production validation

#### Test Infrastructure Scripts
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

## Performance and Optimization

### Test Performance Targets

- **Development Environment**: <1 minute execution time
- **CI Environment**: <3 minutes execution time
- **Production Environment**: <10 minutes execution time

### Parallel Test Execution

The testing strategy utilizes parallel test execution for optimal performance:
- Multiple test suites can run concurrently
- Environment-specific optimizations for different test types
- Cached dependencies and build artifacts for faster execution

## Validation Strategy

### Complete Local Validation

Before submitting changes, run the complete validation sequence:

```bash
# Complete validation sequence (matches CI pipeline)
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

### Environment Validation

```bash
# Using the provided setup script
./Scripts/test-environment-setup.sh validate

# Verify QEMU test server functionality
./Scripts/qemu-test-validation.sh validate-environment
```

## Continuous Integration Integration

### CI Pipeline Testing

The testing strategy integrates with GitHub Actions CI pipeline:

- **Unit Tests Job**: Validates functionality through automated unit tests
- **Integration Tests Job**: End-to-end validation with QEMU test server
- **Build Validation**: Ensures compilation and bundle creation
- **Code Quality**: SwiftLint validation

### Local CI Validation

```bash
# Run all checks in sequence (mimics CI pipeline)
swiftlint lint --strict
swift build --verbose
swift test --parallel --verbose
./Scripts/qemu-test-validation.sh
```

## Troubleshooting Test Issues

### Test Failure Diagnosis

```bash
# Run tests with detailed output
swift test --verbose --parallel

# Run specific test suite for focused debugging
swift test --filter USBIPDCoreTests
swift test --filter USBIPDCLITests

# System Extension specific debugging
swift test --filter SystemExtensionInstallationTests
```

### Environment-Specific Issues

- **Development Environment**: Check mock configurations and test data
- **CI Environment**: Verify no hardware dependencies in test execution
- **Production Environment**: Ensure QEMU server availability and System Extension permissions

This comprehensive testing strategy ensures reliable functionality across all components while supporting the unique requirements of macOS System Extension development and USB/IP protocol implementation.