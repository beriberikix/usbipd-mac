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
- **USBIPDCoreTests**: Core functionality unit tests
- **USBIPDCLITests**: CLI interface unit tests  
- **IntegrationTests**: End-to-end tests with QEMU validation

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
# Run all tests
swift test --parallel --verbose

# Run specific test suite
swift test --filter USBIPDCoreTests
swift test --filter USBIPDCLITests
swift test --filter IntegrationTests

# QEMU integration tests
./Scripts/run-qemu-tests.sh
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
swift test --parallel --verbose
./Scripts/run-qemu-tests.sh
swift test --filter IntegrationTests --verbose
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

- Unit tests for core functionality
- Integration tests with QEMU server validation
- Parallel test execution for performance
- CI pipeline with comprehensive validation

## Scripts

Located in `Scripts/` directory:
- `run-qemu-tests.sh`: Main QEMU integration test runner
- `qemu-test-validation.sh`: QEMU server validation
- Various test scenario scripts in `Scripts/examples/`