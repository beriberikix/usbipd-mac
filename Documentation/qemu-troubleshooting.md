# QEMU USB/IP Test Tool - Troubleshooting Guide

## Overview

This guide provides solutions for common issues encountered when using the QEMU USB/IP test tool. The tool is designed to be robust, but various environmental factors can cause problems.

## Quick Diagnostics

Before diving into specific issues, run these quick diagnostic commands:

```bash
# Check QEMU installation
qemu-system-x86_64 --version

# Check available disk space
df -h .build/qemu/

# Check for running QEMU processes
ps aux | grep qemu

# Check network port availability
lsof -i :2222
lsof -i :3240

# Verify script permissions
ls -la Scripts/*.sh
```

## Common Issues and Solutions

### 1. Image Creation Failures

#### Issue: "Failed to download Alpine Linux ISO"

**Symptoms:**
- Error message about network connectivity
- Checksum validation failures
- Timeout during download

**Solutions:**

```bash
# Check network connectivity
curl -I https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/

# Clear any partial downloads
rm -rf .build/qemu/downloads/

# Try with different mirror (edit create-qemu-image.sh)
# Change ALPINE_URL to use a different mirror

# Run with debug output
DEBUG=1 ./Scripts/create-qemu-image.sh
```

**Alternative mirrors:**
- `http://mirror.math.princeton.edu/pub/alpinelinux/`
- `https://mirrors.edge.kernel.org/alpine/`
- `https://mirror.leaseweb.com/alpine/`

#### Issue: "Insufficient disk space"

**Symptoms:**
- Error during image creation
- "No space left on device" messages

**Solutions:**

```bash
# Check available space
df -h .build/

# Clean up old builds
rm -rf .build/qemu/old-images/
rm -rf .build/qemu/logs/*.log

# Reduce image size (edit create-qemu-image.sh)
# Change DISK_SIZE from "512M" to "256M"
```

#### Issue: "QEMU image creation tools not found"

**Symptoms:**
- "qemu-img: command not found"
- Missing QEMU utilities

**Solutions:**

```bash
# Install QEMU on macOS
brew install qemu

# Verify installation
which qemu-img
which qemu-system-x86_64

# Check PATH
echo $PATH | grep -o '/[^:]*qemu[^:]*'
```

### 2. QEMU Startup Issues

#### Issue: "QEMU fails to start"

**Symptoms:**
- Process exits immediately
- No console output
- Permission denied errors

**Solutions:**

```bash
# Check image file exists and is readable
ls -la .build/qemu/qemu-usbip-client.qcow2

# Verify image integrity
qemu-img check .build/qemu/qemu-usbip-client.qcow2

# Test with minimal configuration
qemu-system-x86_64 -m 128M -nographic -drive file=.build/qemu/qemu-usbip-client.qcow2,format=qcow2

# Check for hardware acceleration issues
qemu-system-x86_64 -accel help
```

#### Issue: "Boot timeout - VM doesn't start"

**Symptoms:**
- QEMU process starts but VM doesn't boot
- Console shows no output or hangs
- Timeout errors in logs

**Solutions:**

```bash
# Increase boot timeout
BOOT_TIMEOUT=120 ./Scripts/start-qemu-client.sh

# Check console output manually
tail -f .build/qemu/logs/*-console.log

# Try without hardware acceleration
# Edit start-qemu-client.sh and remove -accel hvf

# Test with different machine type
# Edit start-qemu-client.sh and change QEMU_MACHINE to "pc"
```

#### Issue: "Network port conflicts"

**Symptoms:**
- "Address already in use" errors
- Cannot bind to port 2222 or 3240
- Multiple QEMU instances conflict

**Solutions:**

```bash
# Find processes using the ports
lsof -i :2222
lsof -i :3240

# Kill conflicting processes
pkill -f "qemu.*2222"

# Use different ports
HOST_SSH_PORT=2223 HOST_USBIP_PORT=3241 ./Scripts/start-qemu-client.sh

# Enable automatic port allocation
# This is built into the script - it will find available ports
```

### 3. USB/IP Client Issues

#### Issue: "USB/IP client not ready"

**Symptoms:**
- Timeout waiting for client readiness
- Missing "USBIP_CLIENT_READY" message
- vhci-hcd module not loaded

**Solutions:**

```bash
# Check console log for errors
grep -i error .build/qemu/logs/*-console.log

# Look for kernel module messages
grep -i vhci .build/qemu/logs/*-console.log

# Check if usbip tools are installed
grep -i usbip .build/qemu/logs/*-console.log

# Recreate image with debug output
DEBUG=1 ./Scripts/create-qemu-image.sh
```

#### Issue: "Cannot connect to USB/IP server"

**Symptoms:**
- Connection refused errors
- Network unreachable messages
- Server connectivity test failures

**Solutions:**

```bash
# Test server connectivity from host
telnet localhost 3240

# Check if usbipd-mac server is running
ps aux | grep usbipd

# Verify network configuration in QEMU
# Check that port forwarding is working
ssh -p 2222 testuser@localhost "netstat -an | grep 3240"

# Test with different server address
./Scripts/examples/basic-usbip-test.sh 127.0.0.1 3240
```

### 4. Performance Issues

#### Issue: "QEMU instances use too much memory"

**Symptoms:**
- High memory usage
- System becomes slow
- Out of memory errors

**Solutions:**

```bash
# Reduce memory allocation
QEMU_MEMORY=128M ./Scripts/start-qemu-client.sh

# Monitor memory usage
./Scripts/test-resource-optimization.sh

# Limit concurrent instances
# Reduce CONCURRENT_CLIENTS in advanced test scripts

# Check for memory leaks
ps aux | grep qemu | awk '{print $2, $6}' # PID and memory usage
```

#### Issue: "Slow boot times"

**Symptoms:**
- Long delays during VM startup
- Timeouts during boot process
- Poor performance in CI

**Solutions:**

```bash
# Enable hardware acceleration (if available)
# Ensure -accel hvf is in start-qemu-client.sh

# Use faster disk format
# Consider using raw format instead of qcow2 for speed

# Optimize Alpine Linux configuration
# Remove unnecessary services from cloud-init

# Check host system performance
top
iostat 1 5
```

### 5. CI/CD Integration Issues

#### Issue: "Tests fail in GitHub Actions"

**Symptoms:**
- Tests pass locally but fail in CI
- Virtualization not available
- Resource constraints in CI

**Solutions:**

```bash
# Check if virtualization is available in CI
# Add this to your GitHub Actions workflow:
# - name: Check virtualization
#   run: |
#     ls -la /dev/kvm || echo "KVM not available"
#     qemu-system-x86_64 -accel help

# Use software emulation in CI
# Modify start-qemu-client.sh to detect CI environment
if [[ "${CI:-}" == "true" ]]; then
    # Remove hardware acceleration
    QEMU_ACCEL=""
fi

# Increase timeouts for CI
if [[ "${CI:-}" == "true" ]]; then
    BOOT_TIMEOUT=180
fi
```

#### Issue: "Insufficient resources in CI"

**Symptoms:**
- Out of memory errors
- Disk space issues
- Timeout errors

**Solutions:**

```bash
# Reduce resource usage for CI
if [[ "${CI:-}" == "true" ]]; then
    QEMU_MEMORY=128M
    CONCURRENT_CLIENTS=1
fi

# Clean up between test runs
# Add cleanup steps to GitHub Actions workflow

# Use caching for QEMU images
# Cache .build/qemu/ directory in GitHub Actions
```

### 6. Logging and Debugging Issues

#### Issue: "Cannot parse console output"

**Symptoms:**
- Validation scripts fail
- Missing structured log messages
- Incorrect log format

**Solutions:**

```bash
# Check log file format
head -20 .build/qemu/logs/*-console.log

# Verify timestamp format
grep -E '^\[.*\]' .build/qemu/logs/*-console.log | head -5

# Test log parsing manually
./Scripts/qemu-test-validation.sh parse-log console.log USBIP_CLIENT_READY

# Enable debug logging in cloud-init
# Edit cloud-init configuration to add more verbose output
```

#### Issue: "Log files not created"

**Symptoms:**
- Missing console log files
- Empty log directories
- No diagnostic information

**Solutions:**

```bash
# Check log directory permissions
ls -la .build/qemu/logs/

# Verify QEMU serial console configuration
# Ensure -serial file:... is in QEMU command line

# Check for disk space issues
df -h .build/qemu/

# Test with manual QEMU startup
qemu-system-x86_64 -m 256M -nographic \
  -drive file=.build/qemu/qemu-usbip-client.qcow2,format=qcow2 \
  -serial file:test-console.log
```

## Advanced Debugging

### Enable Debug Mode

Set the DEBUG environment variable to get verbose output:

```bash
export DEBUG=1
./Scripts/create-qemu-image.sh
./Scripts/start-qemu-client.sh
./Scripts/qemu-test-validation.sh
```

### Manual QEMU Debugging

Start QEMU manually with debugging options:

```bash
# Start with monitor console
qemu-system-x86_64 -m 256M -nographic \
  -drive file=.build/qemu/qemu-usbip-client.qcow2,format=qcow2 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::3240-:3240 \
  -device virtio-net-pci,netdev=net0 \
  -monitor stdio

# In QEMU monitor, you can:
# (qemu) info network
# (qemu) info block
# (qemu) info status
```

### Cloud-init Debugging

Check cloud-init logs inside the VM:

```bash
# SSH into the VM
ssh -p 2222 testuser@localhost

# Check cloud-init status
sudo cloud-init status

# View cloud-init logs
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log
```

### Network Debugging

Test network connectivity step by step:

```bash
# Test host to VM SSH
ssh -p 2222 testuser@localhost "echo 'SSH works'"

# Test VM to host connectivity
ssh -p 2222 testuser@localhost "ping -c 3 10.0.2.2"

# Test USB/IP port forwarding
ssh -p 2222 testuser@localhost "nc -zv 10.0.2.2 3240"

# Check USB/IP client tools
ssh -p 2222 testuser@localhost "usbip version"
ssh -p 2222 testuser@localhost "lsmod | grep vhci"
```

## Performance Optimization

### Resource Tuning

Optimize for your environment:

```bash
# For development (more resources)
export QEMU_MEMORY=512M
export QEMU_CPU_COUNT=2

# For CI (minimal resources)
export QEMU_MEMORY=128M
export QEMU_CPU_COUNT=1

# For testing (balanced)
export QEMU_MEMORY=256M
export QEMU_CPU_COUNT=1
```

### Disk Optimization

Improve disk performance:

```bash
# Use SSD storage for .build directory
# Ensure .build is on fast storage

# Optimize QCOW2 images
qemu-img convert -O qcow2 -c old-image.qcow2 optimized-image.qcow2

# Use raw format for better performance (larger size)
qemu-img convert -O raw image.qcow2 image.raw
```

### Network Optimization

Improve network performance:

```bash
# Use virtio network driver (already configured)
# Ensure host has good network connectivity
# Consider using bridge networking for better performance
```

## Getting Help

### Collecting Diagnostic Information

When reporting issues, collect this information:

```bash
# System information
uname -a
qemu-system-x86_64 --version
brew list | grep qemu

# Project state
ls -la .build/qemu/
ls -la Scripts/
git status

# Recent logs
tail -50 .build/qemu/logs/*-console.log
tail -50 .build/qemu/image-creation.log

# Process information
ps aux | grep qemu
lsof -i :2222
lsof -i :3240
```

### Log Analysis

Use the built-in analysis tools:

```bash
# Generate comprehensive report
./Scripts/qemu-test-validation.sh generate-report console.log report.txt

# Get statistics
./Scripts/qemu-test-validation.sh get-stats console.log

# Validate log format
./Scripts/qemu-test-validation.sh validate-format console.log
```

### Community Resources

- Check the project's GitHub issues for similar problems
- Review the USB/IP protocol specification
- Consult QEMU documentation for virtualization issues
- Check Alpine Linux documentation for guest OS issues

## Prevention

### Best Practices

1. **Regular Cleanup**: Clean up old builds and logs regularly
2. **Resource Monitoring**: Monitor system resources during testing
3. **Version Pinning**: Use specific versions of dependencies
4. **Automated Testing**: Run tests regularly to catch regressions
5. **Documentation**: Keep troubleshooting notes for your environment

### Monitoring

Set up monitoring for long-running tests:

```bash
# Monitor resource usage
./Scripts/test-resource-optimization.sh

# Monitor log growth
watch -n 5 'du -sh .build/qemu/logs/'

# Monitor QEMU processes
watch -n 5 'ps aux | grep qemu'
```

This troubleshooting guide should help resolve most common issues with the QEMU USB/IP test tool. For persistent problems, consider the advanced debugging techniques and don't hesitate to collect diagnostic information for further analysis.