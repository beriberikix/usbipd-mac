# QEMU Test Tool Troubleshooting

This document provides troubleshooting guidance for the current QEMU test tool implementation, focusing on the test validation utilities and placeholder test server.

## Current Implementation Issues

### Test Validation Utility Issues

#### Log Parsing Failures

**Symptoms**: The validation script fails to parse console logs or reports no structured messages found.

**Diagnosis**:
```bash
# Check log file format
./Scripts/qemu-test-validation.sh validate-format console.log

# View raw log content
head -20 console.log

# Check for structured messages
./Scripts/qemu-test-validation.sh parse-log console.log
```

**Solutions**:
- Ensure log files use the correct structured format: `[YYYY-MM-DD HH:MM:SS.mmm] MESSAGE_TYPE: details`
- Verify log files are not empty or corrupted
- Check file permissions for log files
- Use absolute paths when referencing log files

#### Environment Detection Issues

**Symptoms**: Script fails to detect correct test environment or uses wrong timeout values.

**Diagnosis**:
```bash
# Check current environment detection
./Scripts/qemu-test-validation.sh environment-info

# Verify environment variables
echo "CI: ${CI:-unset}"
echo "GITHUB_ACTIONS: ${GITHUB_ACTIONS:-unset}"
echo "TEST_ENVIRONMENT: ${TEST_ENVIRONMENT:-unset}"
```

**Solutions**:
- Set explicit environment: `TEST_ENVIRONMENT=ci ./Scripts/qemu-test-validation.sh`
- Verify CI environment variables are set correctly
- Check script permissions and execution context

#### Server Connectivity Problems

**Symptoms**: Server connectivity tests fail even when server is running.

**Diagnosis**:
```bash
# Test basic connectivity
nc -z localhost 3240

# Check if USB/IP server is running
lsof -i :3240

# Test with different timeout
./Scripts/qemu-test-validation.sh check-server localhost 3240
```

**Solutions**:
- Ensure USB/IP server is running and listening on correct port
- Check firewall settings blocking local connections
- Verify network configuration allows local connections
- Install required tools: `brew install netcat` (if using nc)

#### Timeout Configuration Issues

**Symptoms**: Tests timeout prematurely or take too long in certain environments.

**Diagnosis**:
```bash
# Check current timeout configuration
./Scripts/qemu-test-validation.sh environment-info

# Test with custom timeouts
TEST_ENVIRONMENT=development ./Scripts/qemu-test-validation.sh wait-readiness console.log 30
```

**Solutions**:
- Adjust environment-specific timeouts by setting `TEST_ENVIRONMENT`
- Use longer timeouts for slower systems: `TEST_ENVIRONMENT=production`
- For CI environments, ensure reasonable timeout values (60-120s)

### Placeholder Test Server Issues

#### Build Failures

**Symptoms**: QEMUTestServer fails to build with Swift Package Manager.

**Diagnosis**:
```bash
# Build with verbose output
swift build --product QEMUTestServer --verbose

# Check for compilation errors
swift build --product QEMUTestServer 2>&1 | grep error
```

**Solutions**:
- Ensure Swift toolchain is properly installed
- Clean build directory: `swift package clean`
- Update dependencies: `swift package resolve`
- Check Package.swift configuration for QEMUTestServer target

#### Runtime Issues

**Symptoms**: QEMUTestServer crashes or doesn't start properly.

**Diagnosis**:
```bash
# Run with direct execution
./.build/debug/QEMUTestServer

# Check for runtime errors
swift run QEMUTestServer 2>&1
```

**Solutions**:
- Current implementation is a placeholder - limited functionality expected
- Check console output for error messages
- Verify system permissions for executable

## Environment-Specific Troubleshooting

### Development Environment

**Common Issues**:
- Faster timeouts may cause false failures on slower development machines
- Log parsing issues when testing with incomplete logs

**Solutions**:
```bash
# Use development-friendly settings
TEST_ENVIRONMENT=development ./Scripts/qemu-test-validation.sh check-readiness console.log

# Allow partial validation
./Scripts/qemu-test-validation.sh environment-validation console.log basic
```

### CI Environment

**Common Issues**:
- Environment detection failures in CI runners
- Network connectivity restrictions
- Missing system tools (nc, telnet)

**Solutions**:
```bash
# Explicit CI environment setting
TEST_ENVIRONMENT=ci ./Scripts/qemu-test-validation.sh validate-environment

# Install required tools in CI
brew install netcat
```

### Production Environment

**Common Issues**:
- Extended timeouts may be too long for some use cases
- Comprehensive validation may fail on resource-constrained systems

**Solutions**:
```bash
# Adjust validation level
./Scripts/qemu-test-validation.sh environment-validation console.log basic

# Monitor resource usage
top -l 1 | grep -E "(CPU|Memory)"
```

## Future Implementation Issues

### Missing QEMU Functionality

**Current Limitation**: Full QEMU testing framework (image creation, VM management) is not yet implemented.

**Workarounds**:
- Use existing test validation utilities for log analysis
- Implement custom test scenarios using the placeholder test server
- Focus on unit and integration tests rather than full QEMU testing

**Planned Solutions**:
- QEMU image creation scripts (planned)
- VM lifecycle management utilities (planned)
- Automated testing framework (future development)

### Limited Test Server Functionality

**Current Limitation**: QEMUTestServer is a minimal placeholder.

**Workarounds**:
- Use other testing methods for USB/IP protocol validation
- Develop against the main usbipd server implementation
- Implement mock test scenarios for development

## Diagnostic Commands

### Comprehensive System Check

```bash
# Check all components
echo "=== Environment ==="
./Scripts/qemu-test-validation.sh environment-info

echo "=== Build Status ==="
swift build --product QEMUTestServer

echo "=== Script Availability ==="
ls -la Scripts/qemu-test-validation.sh

echo "=== System Tools ==="
which nc || echo "netcat not available"
which telnet || echo "telnet not available"
```

### Log Analysis

```bash
# Analyze existing log file
if [ -f console.log ]; then
    echo "=== Log Format Validation ==="
    ./Scripts/qemu-test-validation.sh validate-format console.log
    
    echo "=== Log Statistics ==="
    ./Scripts/qemu-test-validation.sh get-stats console.log
    
    echo "=== Generate Report ==="
    ./Scripts/qemu-test-validation.sh generate-report console.log
else
    echo "No console.log found for analysis"
fi
```

## Getting Help

### Check Current Implementation

1. **Review Documentation**: [QEMU Test Tool](../qemu-test-tool.md) for current capabilities
2. **Test Validation Script**: Run `./Scripts/qemu-test-validation.sh --help` for available commands
3. **Build Status**: Verify `swift build --product QEMUTestServer` works

### Report Issues

When reporting issues with the current implementation:

1. **Specify Component**: Test validation utility vs. placeholder test server
2. **Include Environment**: Development, CI, or production environment
3. **Provide Logs**: Include relevant console logs and error messages
4. **System Info**: Include macOS version, Swift version, and hardware details

### Contributing

For enhancing the current implementation:

1. **Test Validation Utility**: Improve parsing, add validation features, enhance environment detection
2. **Placeholder Test Server**: Implement basic USB/IP protocol support
3. **Future Features**: Contribute to planned QEMU image and VM management capabilities

## References

- [QEMU Test Tool Documentation](../qemu-test-tool.md) - Current implementation overview
- [Testing Strategy](../development/testing-strategy.md) - Overall project testing approach
- [Build Troubleshooting](build-troubleshooting.md) - General build issues