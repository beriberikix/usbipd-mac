# QEMU Test Tool Troubleshooting

This document provides troubleshooting guidance for the QEMU USB/IP Test Tool.

## Common Issues

### Image Creation Failures

**Symptoms**: QEMU image creation script fails during download or image creation process.

**Diagnosis**:
```bash
# Check available disk space
df -h .build/qemu/

# Verify QEMU installation
qemu-system-x86_64 --version

# Check network connectivity for downloads
curl -I https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/
```

**Solutions**:
- Ensure sufficient disk space (minimum 1GB free)
- Install or update QEMU: `brew install qemu`
- Check internet connectivity and proxy settings
- Verify write permissions in `.build/qemu/` directory

### Boot Timeouts

**Symptoms**: QEMU instance fails to boot within the timeout period, hanging at boot process.

**Diagnosis**:
```bash
# Check console log for boot progress
tail -f .build/qemu/logs/{instance-id}-console.log

# Verify image integrity
qemu-img check .build/qemu/qemu-usbip-client.qcow2

# Test with increased timeout
BOOT_TIMEOUT=120 ./Scripts/start-qemu-client.sh
```

**Solutions**:
- Increase boot timeout: `BOOT_TIMEOUT=120`
- Recreate QEMU image if corrupted
- Check system resources (CPU/memory availability)
- Disable hardware acceleration if causing issues

### Network Issues

**Symptoms**: Unable to connect to QEMU instance via SSH or USB/IP protocol.

**Diagnosis**:
```bash
# Check port availability
lsof -i :2222
lsof -i :3240

# Test with different ports
HOST_SSH_PORT=2223 HOST_USBIP_PORT=3241 ./Scripts/start-qemu-client.sh
```

**Solutions**:
- Use alternative ports if defaults are occupied
- Check firewall settings and port forwarding
- Verify QEMU networking configuration
- Restart network services if needed

### QEMU Process Crashes

**Symptoms**: QEMU process terminates unexpectedly during execution.

**Diagnosis**:
- Check crash logs in `.build/qemu/logs/qemu-crash-{instance-id}.log`
- Verify system compatibility and hardware acceleration support
- Monitor system resources during execution

**Solutions**:
- Disable hardware acceleration: add `-accel tcg` to QEMU args
- Reduce memory allocation: `QEMU_MEMORY=128M`
- Update QEMU to latest version
- Check for conflicting virtualization software

## Debug Mode

Enable verbose logging for detailed troubleshooting:

```bash
# Enable debug output for all scripts
export DEBUG=1
./Scripts/create-qemu-image.sh
```

**Debug Features**:
- Detailed command execution logging
- Network configuration diagnostics
- Resource usage monitoring
- Extended error reporting

## Log Analysis

Use the validation script for comprehensive log analysis:

```bash
# Get comprehensive test statistics
./Scripts/qemu-test-validation.sh get-stats console.log

# Validate log format and structure
./Scripts/qemu-test-validation.sh validate-format console.log

# Generate detailed test report
./Scripts/qemu-test-validation.sh generate-report console.log report.txt
```

## Error Detection and Recovery

### Automatic Error Detection

The tool automatically detects and handles:

- **Boot Timeouts**: Detects stalled boot processes and provides diagnostic information
- **Network Failures**: Identifies port conflicts and connectivity issues
- **QEMU Crashes**: Captures process failures with detailed crash diagnostics
- **Resource Constraints**: Monitors disk space and memory availability

### Diagnostic Files

When errors occur, diagnostic files are automatically generated:

```
.build/qemu/logs/
├── diagnostics-{instance-id}.log     # General failure diagnostics
├── boot-timeout-{instance-id}.log    # Boot timeout analysis
├── network-failure-{instance-id}.log # Network configuration issues
└── qemu-crash-{instance-id}.log      # QEMU process crash details
```

### Retry Mechanisms

The tool includes automatic retry logic for:

- **Download Retries**: Automatic retry with exponential backoff for network downloads
- **Port Availability**: Retry logic for network port conflicts
- **Boot Process**: Multiple boot attempts with different configurations
- **Connection Validation**: Persistent retry for server connectivity checks

## Performance Issues

### Resource Constraints

**Memory Issues**:
- Reduce QEMU memory allocation: `QEMU_MEMORY=128M`
- Limit concurrent instances
- Monitor system memory usage

**Disk Space Issues**:
- Clean up old QEMU images: `rm -rf .build/qemu/old-*`
- Use QCOW2 compression for space efficiency
- Monitor disk space before operations

**CPU Performance**:
- Adjust CPU core allocation: `QEMU_CPU_COUNT=1`
- Enable hardware acceleration when available
- Avoid CPU-intensive background processes during testing

## CI Environment Issues

### GitHub Actions Specific Issues

**Runner Resource Limits**:
- Use optimized resource allocation for CI
- Enable aggressive caching for faster builds
- Monitor CI runner performance metrics

**Network Connectivity**:
- Handle intermittent network failures in CI
- Use retry mechanisms for download operations
- Cache Alpine Linux images to reduce download needs

**Permission Issues**:
- Ensure proper file permissions in CI environment
- Use user mode networking to avoid privilege requirements
- Verify write access to build directories

## Getting Help

If troubleshooting steps don't resolve the issue:

1. **Enable Debug Mode**: Run with `DEBUG=1` for verbose output
2. **Collect Logs**: Gather all relevant log files from `.build/qemu/logs/`
3. **Check System Requirements**: Verify QEMU installation and system compatibility
4. **Test Environment**: Validate that basic QEMU functionality works outside the tool
5. **Report Issues**: Include debug logs and system information when reporting problems

## Additional Resources

- [QEMU Test Tool Documentation](../qemu-test-tool.md) - Complete tool documentation
- [Build Troubleshooting](build-troubleshooting.md) - General build issues
- [QEMU Documentation](https://www.qemu.org/docs/master/) - Official QEMU documentation
- [Alpine Linux Documentation](https://wiki.alpinelinux.org/) - Alpine Linux specific guidance