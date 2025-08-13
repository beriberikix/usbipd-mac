# QEMU Test Tool

## Overview

The QEMU test tool components provide testing infrastructure for validating USB/IP protocol implementation. Currently, this consists of test validation utilities and a placeholder test server, with plans for expanded QEMU-based testing capabilities.

## Current Implementation Status

### Available Components

#### Test Validation Utility (`Scripts/qemu-test-validation.sh`)
A comprehensive script for parsing and validating test logs with environment-aware functionality:

- **Console Log Parsing**: Extracts structured messages from test output
- **Environment Detection**: Automatically detects development, CI, or production environments  
- **USB/IP Client Validation**: Checks for client readiness and functionality
- **Server Connectivity Testing**: Validates USB/IP server connectivity
- **Test Report Generation**: Creates detailed test reports with statistics
- **Multi-Environment Support**: Adapts timeouts and validation based on test environment

#### Placeholder Test Server (`Sources/QEMUTestServer/`)
A minimal Swift executable that serves as a foundation for future QEMU test server implementation.

### Architecture

Current test infrastructure:

```
Scripts/
└── qemu-test-validation.sh       # Test validation and log parsing utilities

Sources/
└── QEMUTestServer/
    └── main.swift                # Placeholder test server executable
```

## Using the Test Validation Utility

### Basic Usage

```bash
# Parse structured log messages
./Scripts/qemu-test-validation.sh parse-log console.log

# Check if USB/IP client is ready
./Scripts/qemu-test-validation.sh check-readiness console.log

# Wait for client readiness with timeout
./Scripts/qemu-test-validation.sh wait-readiness console.log 60

# Generate comprehensive test report
./Scripts/qemu-test-validation.sh generate-report console.log
```

### Environment-Aware Testing

The validation utility automatically detects and adapts to different test environments:

```bash
# Automatic environment detection
./Scripts/qemu-test-validation.sh environment-info

# Explicit environment setting
TEST_ENVIRONMENT=ci ./Scripts/qemu-test-validation.sh validate-environment

# Environment-specific validation
./Scripts/qemu-test-validation.sh environment-validation console.log full
```

### Server Connectivity Testing

```bash
# Check basic server connectivity
./Scripts/qemu-test-validation.sh check-server localhost 3240

# Test server response (requires usbip client tools)
./Scripts/qemu-test-validation.sh test-server localhost 3240

# Monitor connection over time
./Scripts/qemu-test-validation.sh monitor-connection console.log localhost 3240 120
```

## Structured Logging Format

The validation utility expects structured log messages in this format:

```
[YYYY-MM-DD HH:MM:SS.mmm] MESSAGE_TYPE: details
```

### Supported Message Types

- `USBIP_CLIENT_READY` - USB/IP client initialization complete
- `VHCI_MODULE_LOADED: SUCCESS/FAILED` - Kernel module loading status  
- `USBIP_VERSION: version_info` - USB/IP client version information
- `CONNECTING_TO_SERVER: host:port` - Server connection attempts
- `DEVICE_LIST_REQUEST: SUCCESS/FAILED` - Device enumeration results
- `DEVICE_IMPORT_REQUEST: device_id SUCCESS/FAILED` - Device import operations
- `TEST_COMPLETE: SUCCESS/FAILED` - Overall test completion status

### Example Log Output

```
[2024-01-15 10:30:15.123] USBIP_STARTUP_BEGIN
[2024-01-15 10:30:15.456] VHCI_MODULE_LOADED: SUCCESS
[2024-01-15 10:30:16.234] USBIP_VERSION: usbip (usbip-utils 2.0)
[2024-01-15 10:30:16.456] USBIP_CLIENT_READY
[2024-01-15 10:30:20.567] CONNECTING_TO_SERVER: 192.168.1.100:3240
[2024-01-15 10:30:21.789] DEVICE_LIST_REQUEST: SUCCESS
[2024-01-15 10:30:23.234] TEST_COMPLETE: SUCCESS
```

## Environment-Specific Behavior

### Development Environment
- **Timeouts**: Shorter timeouts for fast feedback (30s readiness, 5s connection)
- **Validation**: Basic validation with partial completion allowed
- **Use Case**: Local development and IDE integration

### CI Environment  
- **Timeouts**: Moderate timeouts for reliable automation (60s readiness, 10s connection)
- **Validation**: Comprehensive validation requiring full completion
- **Use Case**: Pull request validation and automated testing

### Production Environment
- **Timeouts**: Extended timeouts for thorough testing (120s readiness, 30s connection)
- **Validation**: Exhaustive validation with detailed reporting
- **Use Case**: Release candidate validation and comprehensive testing

## CI Integration

The validation utility integrates with the project's CI pipeline:

```bash
# Run QEMU validation (as used in CI)
./Scripts/qemu-test-validation.sh
```

Integration with test suites:

```bash
# Run all tests including QEMU validation
swift test

# Run only QEMU-related validation tests  
swift test --filter QEMUTestValidationTests
```

## Available Commands

### Standard Commands
- `parse-log <file> [type]` - Parse console log messages
- `check-readiness <file>` - Check USB/IP client readiness
- `wait-readiness <file> [timeout]` - Wait for client readiness
- `validate-test <file>` - Validate test completion
- `generate-report <file> [output]` - Generate test report
- `check-server <host> [port]` - Check server connectivity
- `validate-format <file>` - Validate log format
- `get-stats <file>` - Get test statistics

### Environment-Aware Commands
- `validate-environment` - Validate current test environment
- `environment-validation <file> [type]` - Run environment-aware validation
- `monitor-execution <file> [host] [port]` - Environment-aware test monitoring
- `environment-info` - Show current environment configuration

## Future Development

### Planned Features

The following components are planned for future implementation:

- **QEMU Image Creation**: Scripts for creating minimal Linux images with USB/IP client capabilities
- **QEMU Instance Management**: VM lifecycle management with optimized resource allocation
- **Automated Testing Framework**: End-to-end testing with virtual USB/IP clients
- **CI Pipeline Integration**: Comprehensive QEMU-based validation in GitHub Actions

### Development Roadmap

1. **Phase 1**: Enhanced test server implementation with basic USB/IP protocol support
2. **Phase 2**: QEMU image creation and management utilities
3. **Phase 3**: Full automated testing framework with virtual client support
4. **Phase 4**: Advanced features like concurrent testing and performance benchmarking

## Troubleshooting

For issues with the current test validation utilities, see the [QEMU Troubleshooting Guide](troubleshooting/qemu-troubleshooting.md).

Common issues with current implementation:
- Log parsing failures due to incorrect format
- Environment detection issues in CI
- Server connectivity problems
- Timeout configuration for different environments

## Contributing

When working on QEMU test tool development:

1. **Current Focus**: Enhance the test validation utilities and placeholder test server
2. **Future Development**: Contribute to planned QEMU image and VM management features
3. **Testing**: Use existing validation utilities to test changes
4. **Documentation**: Keep this documentation updated as functionality is implemented

### Testing Changes

```bash
# Test validation utility functionality
./Scripts/qemu-test-validation.sh --help
./Scripts/qemu-test-validation.sh environment-info

# Build placeholder test server
swift build --product QEMUTestServer

# Run project test suites
swift test
```

## References

- [USB/IP Protocol Specification](https://www.kernel.org/doc/html/latest/usb/usbip_protocol.html)
- [Testing Strategy Documentation](development/testing-strategy.md) - Project testing approach
- [QEMU Troubleshooting Guide](troubleshooting/qemu-troubleshooting.md) - Issue resolution

## License

This tool is part of the usbipd-mac project and is licensed under the MIT License.