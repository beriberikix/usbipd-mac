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

### Key Features
- Environment-specific mock libraries for reliable testing
- Conditional hardware detection and graceful degradation
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