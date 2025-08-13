# QEMU USB/IP Test Tool

## Overview

The QEMU USB/IP Test Tool is a comprehensive testing framework that provides automated validation of the usbipd-mac server implementation using minimal QEMU virtual machines. The tool creates lightweight Linux environments that act as USB/IP clients, enabling end-to-end testing of the USB/IP protocol implementation.

## Features

- **Automated Image Creation**: Creates minimal Alpine Linux images with USB/IP client capabilities
- **QEMU Instance Management**: Launches and manages QEMU virtual machines with optimized resource allocation
- **Structured Logging**: Provides standardized output for automated test validation
- **Error Handling**: Comprehensive error detection and recovery mechanisms
- **CI Integration**: Designed for seamless integration with GitHub Actions CI pipeline
- **Resource Optimization**: Minimal memory and disk usage suitable for CI environments

## Architecture

The tool consists of several interconnected components:

```
Scripts/
├── create-qemu-image.sh          # Image creation and configuration
├── start-qemu-client.sh          # QEMU instance management
├── qemu-test-validation.sh       # Test output parsing and validation
├── test-error-handling.sh        # Error handling mechanism tests
└── test-qemu-logging.sh          # Logging functionality tests
```

### Component Responsibilities

- **Image Creation**: Downloads Alpine Linux, configures USB/IP client tools, and creates bootable QEMU images
- **Instance Management**: Launches QEMU with appropriate networking and resource configuration
- **Test Validation**: Parses structured console output and validates USB/IP client functionality
- **Error Handling**: Provides robust error detection, retry mechanisms, and diagnostic information
- **Logging Tests**: Validates structured logging and output parsing capabilities

## Quick Start

### Prerequisites

```bash
# Install QEMU (required for virtual machine functionality)
brew install qemu

# Install socat (optional, for monitor socket communication)
brew install socat
```

### Basic Usage

1. **Create QEMU Image**:
   ```bash
   ./Scripts/create-qemu-image.sh
   ```

2. **Start QEMU Client**:
   ```bash
   ./Scripts/start-qemu-client.sh
   ```

3. **Validate Test Results**:
   ```bash
   ./Scripts/qemu-test-validation.sh check-readiness console.log
   ```

### CI Integration

The tool is automatically integrated into the GitHub Actions CI pipeline:

```bash
# Run QEMU validation (as used in CI)
./Scripts/run-qemu-tests.sh
```

## Detailed Usage

### Image Creation

The `create-qemu-image.sh` script creates a minimal Linux environment with USB/IP client capabilities:

```bash
# Create image with default configuration
./Scripts/create-qemu-image.sh

# The script will:
# 1. Download Alpine Linux 3.19 with checksum validation
# 2. Create a 512MB QCOW2 disk image
# 3. Configure cloud-init for automated setup
# 4. Install usbip-utils and configure kernel modules
# 5. Set up structured logging and readiness reporting
```

**Output Files**:
- `.build/qemu/qemu-usbip-client.qcow2` - Bootable disk image
- `.build/qemu/cloud-init/` - Cloud-init configuration files
- `.build/qemu/image-creation.log` - Detailed creation log

### QEMU Instance Management

The `start-qemu-client.sh` script manages QEMU virtual machine instances:

```bash
# Start QEMU instance with default configuration
./Scripts/start-qemu-client.sh

# The script provides:
# - Minimal resource allocation (256MB RAM, 1 CPU core)
# - User mode networking with port forwarding
# - Serial console logging to structured output files
# - QEMU monitor socket for command interface
# - Automatic boot timeout and error detection
```

**Network Configuration**:
- SSH access: `ssh -p 2222 testuser@localhost`
- USB/IP port: `localhost:3240`
- Console log: `.build/qemu/logs/{instance-id}-console.log`

### Test Validation

The `qemu-test-validation.sh` script provides comprehensive test validation utilities:

```bash
# Check if USB/IP client is ready
./Scripts/qemu-test-validation.sh check-readiness console.log

# Wait for client readiness with timeout
./Scripts/qemu-test-validation.sh wait-readiness console.log 60

# Parse structured log messages
./Scripts/qemu-test-validation.sh parse-log console.log USBIP_CLIENT_READY

# Generate comprehensive test report
./Scripts/qemu-test-validation.sh generate-report console.log

# Check USB/IP server connectivity
./Scripts/qemu-test-validation.sh check-server localhost 3240

# Monitor connection status over time
./Scripts/qemu-test-validation.sh monitor-connection console.log localhost 3240 120
```

## Structured Logging Format

The tool uses standardized structured logging for automated parsing:

```
[YYYY-MM-DD HH:MM:SS.mmm] MESSAGE_TYPE: details
```

### Key Message Types

- `USBIP_CLIENT_READY` - USB/IP client initialization complete
- `VHCI_MODULE_LOADED: SUCCESS/FAILED` - Kernel module loading status
- `USBIP_VERSION: version_info` - USB/IP client version information
- `CONNECTING_TO_SERVER: host:port` - Server connection attempts
- `DEVICE_LIST_REQUEST: SUCCESS/FAILED` - Device enumeration results
- `DEVICE_IMPORT_REQUEST: device_id SUCCESS/FAILED` - Device import operations
- `TEST_COMPLETE: SUCCESS/FAILED` - Overall test completion status

### Example Console Output

```
[2024-01-15 10:30:15.123] USBIP_STARTUP_BEGIN
[2024-01-15 10:30:15.456] VHCI_MODULE_LOADED: SUCCESS
[2024-01-15 10:30:16.234] USBIP_VERSION: usbip (usbip-utils 2.0)
[2024-01-15 10:30:16.456] USBIP_CLIENT_READY
[2024-01-15 10:30:20.567] CONNECTING_TO_SERVER: 192.168.1.100:3240
[2024-01-15 10:30:21.789] DEVICE_LIST_REQUEST: SUCCESS
[2024-01-15 10:30:23.234] TEST_COMPLETE: SUCCESS
```

## Error Handling and Diagnostics

The tool provides comprehensive error handling and diagnostic capabilities:

### Automatic Error Detection

- **Boot Timeouts**: Detects stalled boot processes and provides diagnostic information
- **Network Failures**: Identifies port conflicts and connectivity issues
- **QEMU Crashes**: Captures process failures with detailed crash diagnostics
- **Resource Constraints**: Monitors disk space and memory availability

### Diagnostic Information

When errors occur, the tool automatically generates diagnostic files:

```
.build/qemu/logs/
├── diagnostics-{instance-id}.log     # General failure diagnostics
├── boot-timeout-{instance-id}.log    # Boot timeout analysis
├── network-failure-{instance-id}.log # Network configuration issues
└── qemu-crash-{instance-id}.log      # QEMU process crash details
```

### Retry Mechanisms

- **Download Retries**: Automatic retry with exponential backoff for network downloads
- **Port Availability**: Retry logic for network port conflicts
- **Boot Process**: Multiple boot attempts with different configurations
- **Connection Validation**: Persistent retry for server connectivity checks

## Testing and Validation

### Unit Tests

The tool includes comprehensive unit tests for all major components:

```bash
# Test error handling mechanisms
./Scripts/test-error-handling.sh

# Test structured logging functionality
./Scripts/test-qemu-logging.sh
```

### Integration Testing

Integration with the main project test suite:

```bash
# Run all tests including QEMU validation
swift test

# Run only QEMU-related integration tests
swift test --filter QEMUTestValidationTests
```

### CI Pipeline Integration

The tool is integrated into the GitHub Actions CI pipeline with the following validation steps:

1. **Build Validation**: Ensures QEMU test server builds successfully
2. **Script Validation**: Runs `run-qemu-tests.sh` to validate basic functionality
3. **Integration Tests**: Executes comprehensive integration test suite
4. **Error Handling**: Validates error detection and recovery mechanisms

## Configuration

### Environment Variables

- `QEMU_MEMORY` - Memory allocation for QEMU instances (default: 256M)
- `QEMU_CPU_COUNT` - CPU core count (default: 1)
- `BOOT_TIMEOUT` - Boot timeout in seconds (default: 60)
- `HOST_SSH_PORT` - SSH port forwarding (default: 2222)
- `HOST_USBIP_PORT` - USB/IP port forwarding (default: 3240)

### Cloud-init Configuration

The tool uses cloud-init for automated VM configuration. Key configuration files:

- `user-data` - User creation, package installation, and startup scripts
- `meta-data` - Instance metadata and identification
- `network-config` - Network interface configuration

### Resource Optimization

The tool is optimized for CI environments with minimal resource requirements:

- **Memory**: 256MB RAM per instance
- **Disk**: ~50MB Alpine Linux base image with QCOW2 compression
- **CPU**: Single core allocation with hardware acceleration when available
- **Network**: User mode networking to avoid privilege requirements

## Troubleshooting

For comprehensive troubleshooting guidance, see the dedicated [QEMU Troubleshooting Guide](troubleshooting/qemu-troubleshooting.md).

Common issues include:
- Image creation failures
- Boot timeouts
- Network connectivity problems
- QEMU process crashes
- Performance issues in CI environments

The troubleshooting guide provides detailed diagnosis steps, solutions, and debug techniques for all QEMU test tool issues.

## Performance Considerations

### Resource Usage

- **Memory**: Each QEMU instance uses ~256MB RAM
- **Disk**: Base image ~50MB, overlay images ~10MB per instance
- **CPU**: Minimal CPU usage with hardware acceleration
- **Network**: User mode networking with minimal overhead

### Concurrent Execution

The tool supports concurrent QEMU instances:

```bash
# Each instance gets unique overlay image and log files
# Network ports are automatically allocated to avoid conflicts
# Resource usage scales linearly with instance count
```

### CI Optimization

- **Caching**: Swift packages and QEMU images are cached between CI runs
- **Parallel Execution**: CI jobs run in parallel for faster feedback
- **Resource Limits**: Optimized for GitHub Actions runner constraints

## Contributing

### Development Guidelines

1. **Follow Project Standards**: Use Swift API Design Guidelines and existing patterns
2. **Maintain Compatibility**: Ensure changes work in CI environment
3. **Add Tests**: Include unit tests for new functionality
4. **Update Documentation**: Keep documentation current with changes

### Testing Changes

```bash
# Test locally before submitting PR
./Scripts/test-error-handling.sh
./Scripts/test-qemu-logging.sh
swift test
./Scripts/run-qemu-tests.sh
```

### Code Style

- Use consistent shell scripting patterns
- Follow project logging conventions
- Maintain structured output format
- Include comprehensive error handling

## References

- [USB/IP Protocol Specification](https://www.kernel.org/doc/html/latest/usb/usbip_protocol.html)
- [QEMU Documentation](https://www.qemu.org/docs/master/)
- [Alpine Linux Documentation](https://wiki.alpinelinux.org/)
- [Cloud-init Documentation](https://cloudinit.readthedocs.io/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

## License

This tool is part of the usbipd-mac project and is licensed under the MIT License.