# System Extension Troubleshooting

This document provides comprehensive troubleshooting guidance for the USB/IP System Extension on macOS.

## Diagnostic Tools

The shell script-based workflow provides comprehensive troubleshooting capabilities:

```bash
# Comprehensive health check
./Scripts/extension-status.sh --health --verbose

# Bundle validation
./Scripts/validate-bundle.sh --deep --verbose

# Environment validation
./Scripts/setup-dev-environment.sh --validate

# View recent logs
./Scripts/extension-status.sh --logs
```

## Common Issues

### 1. System Extension Installation Fails

**Symptoms**: Extension installation is blocked or fails silently

**Diagnostic Steps**:
```bash
# Check environment setup
./Scripts/setup-dev-environment.sh --validate

# Validate bundle structure
./Scripts/validate-bundle.sh

# Check system status
./Scripts/extension-status.sh --system
```

**Solutions**:
- Check SIP status: `./Scripts/setup-dev-environment.sh --check-sip`
- Verify development mode: `systemextensionsctl developer`
- Check System Preferences > Security & Privacy for blocked extensions
- Force reinstall: `./Scripts/install-extension.sh --force`
- Restart the system and try again

### 2. Permission Denied Errors

**Symptoms**: USB device access is denied

**Diagnostic Steps**:
```bash
# Check extension status
./Scripts/extension-status.sh

# Verify bundle signing
./Scripts/validate-bundle.sh --deep
```

**Solutions**:
- Verify the extension is properly loaded: `systemextensionsctl list`
- Check bundle signature: `./Scripts/validate-bundle.sh`
- Ensure proper entitlements and code signing
- Reinstall with proper certificates: `./Scripts/install-extension.sh`

### 3. Device Claiming Fails

**Symptoms**: Devices cannot be claimed for USB/IP sharing

**Diagnostic Steps**:
```bash
# Health check
./Scripts/extension-status.sh --health

# Check recent logs
./Scripts/extension-status.sh --logs
```

**Solutions**:
- Verify System Extension is running: `./Scripts/extension-status.sh`
- Check for conflicting applications using the USB device
- Review system logs for IOKit errors
- Try reinstalling: `./Scripts/install-extension.sh --force`

### 4. Extension Not Loading

**Symptoms**: System Extension appears inactive or not loaded

**Diagnostic Steps**:
```bash
# Check all system extensions
./Scripts/extension-status.sh --all

# Validate environment
./Scripts/setup-dev-environment.sh --validate
```

**Solutions**:
- Check extension permissions in Security & Privacy preferences
- Verify bundle identifier and structure: `./Scripts/validate-bundle.sh`
- Enable development mode: `sudo systemextensionsctl developer on`
- Check system extension staging area: `/Library/SystemExtensions/`
- Force reinstall: `./Scripts/install-extension.sh --force --verbose`

## Debug Commands

The shell script system provides comprehensive debugging tools:

```bash
# Extension-specific debugging
./Scripts/extension-status.sh --verbose --logs
./Scripts/extension-status.sh --watch  # Real-time monitoring
./Scripts/validate-bundle.sh --deep --verbose

# Environment debugging
./Scripts/setup-dev-environment.sh --validate
./Scripts/setup-dev-environment.sh --check-sip
./Scripts/setup-dev-environment.sh --check-certs

# System-level debugging
systemextensionsctl list
systemextensionsctl developer

# Manual log monitoring
log show --predicate 'subsystem == "com.apple.systemextensions"' --last 1h
log show --predicate 'category == "systemextensions"' --last 1h

# Development mode management (use with caution)
sudo systemextensionsctl developer on
sudo systemextensionsctl reset  # Nuclear option - removes all extensions
```

## Log Analysis

Monitor logs in real-time during installation:

```bash
# System extension management logs
log stream --predicate 'subsystem == "com.apple.systemextensions"'

# USB/IP specific logs
log stream --predicate 'subsystem == "com.usbipd.mac"'

# IOKit and USB-related logs
log stream --predicate 'category == "USB"'
```

## Development Troubleshooting

### Bundle Creation Issues

```bash
# Comprehensive bundle validation
./Scripts/validate-bundle.sh --deep --verbose

# Check build output
swift build --verbose

# Validate bundle structure manually
find .build -name "*.systemextension" -exec ls -la {} \;

# Debug bundle creation
./Scripts/install-extension.sh --dry-run --verbose
```

### Installation Issues in Development Mode

```bash
# Environment validation
./Scripts/setup-dev-environment.sh --validate

# Check development mode status
./Scripts/extension-status.sh --system

# Verify certificates
./Scripts/setup-dev-environment.sh --check-certs

# Reset development environment (nuclear option)
sudo systemextensionsctl reset
sudo systemextensionsctl developer on
# (restart required)
./Scripts/setup-dev-environment.sh
```

## System Requirements Issues

### SIP (System Integrity Protection) Problems

**Symptoms**: Extension installation blocked due to SIP

**Diagnosis**:
```bash
# Check SIP status
./Scripts/setup-dev-environment.sh --check-sip

# Manual SIP check
csrutil status
```

**Solutions**:
- SIP must be enabled for System Extensions to work
- If SIP is disabled, re-enable it and restart
- Development mode can be used for unsigned extensions when SIP is enabled

### Development Mode Issues

**Symptoms**: Cannot install unsigned extensions

**Diagnosis**:
```bash
# Check development mode status
systemextensionsctl developer

# Environment validation
./Scripts/setup-dev-environment.sh --validate
```

**Solutions**:
- Enable development mode: `sudo systemextensionsctl developer on`
- Restart the system after enabling development mode
- Verify development mode is active before installing unsigned extensions

### Code Signing Problems

**Symptoms**: Bundle signature verification fails

**Diagnosis**:
```bash
# Check available certificates
./Scripts/setup-dev-environment.sh --check-certs

# Validate bundle signature
./Scripts/validate-bundle.sh --deep

# Manual signature check
codesign -dv --verbose=4 .build/USBIPDSystemExtension.systemextension
```

**Solutions**:
- Ensure proper Developer ID certificates are installed
- Use `--skip-signing` for development builds
- Verify certificate validity and expiration
- Check bundle identifier matches certificate

## Performance and Resource Issues

### High CPU Usage

**Symptoms**: System Extension consuming excessive CPU

**Diagnosis**:
```bash
# Monitor extension performance
./Scripts/extension-status.sh --health --verbose

# Check system activity
top -pid $(pgrep -f "USBIPDSystemExtension")
```

**Solutions**:
- Check for USB device conflicts
- Review extension logs for errors
- Restart the extension: reinstall with `--force`

### Memory Issues

**Symptoms**: System Extension using excessive memory

**Diagnosis**:
```bash
# Memory usage analysis
./Scripts/extension-status.sh --health

# System memory check
vm_stat
```

**Solutions**:
- Monitor for memory leaks in extension code
- Check for device enumeration loops
- Restart extension if memory usage is excessive

## Security and Privacy Issues

### Permission Dialogs Not Appearing

**Symptoms**: macOS security dialogs don't show up

**Solutions**:
- Check System Preferences > Security & Privacy manually
- Restart the installation process
- Verify the extension bundle is properly signed
- Check notification settings for system security alerts

### Entitlements Problems

**Symptoms**: Extension lacks required permissions

**Diagnosis**:
```bash
# Check bundle entitlements
./Scripts/validate-bundle.sh --deep --verbose

# Manual entitlements check
codesign -d --entitlements - .build/USBIPDSystemExtension.systemextension
```

**Solutions**:
- Verify all required entitlements are present
- Check entitlements file in bundle structure
- Ensure proper code signing with entitlements

## Advanced Troubleshooting

### System Extension Reset

If all else fails, completely reset the System Extension environment:

```bash
# Stop all USB/IP processes
sudo pkill usbipd

# Reset all system extensions (nuclear option)
sudo systemextensionsctl reset

# Re-enable development mode if needed
sudo systemextensionsctl developer on

# Restart the system
sudo reboot

# After restart, set up environment again
./Scripts/setup-dev-environment.sh
./Scripts/install-extension.sh --force --verbose
```

### CI/CD Environment Issues

**Symptoms**: Extension builds fail in CI environment

**Diagnosis**:
```bash
# Validate CI environment
./Scripts/setup-dev-environment.sh --validate

# Dry-run installation
./Scripts/install-extension.sh --dry-run --verbose
```

**Solutions**:
- Use `--skip-signing` for CI builds
- Ensure proper build environment setup
- Check for missing dependencies in CI
- Use JSON output for automated parsing: `--json`

## Getting Help

When troubleshooting doesn't resolve the issue:

1. **Collect Diagnostic Information**:
   ```bash
   # Generate comprehensive diagnostics
   ./Scripts/extension-status.sh --health --verbose > diagnostics.log
   ./Scripts/validate-bundle.sh --deep --verbose >> diagnostics.log
   ./Scripts/setup-dev-environment.sh --validate >> diagnostics.log
   ```

2. **Gather System Information**:
   - macOS version: `sw_vers`
   - SIP status: `csrutil status`
   - Development mode status: `systemextensionsctl developer`
   - Extension list: `systemextensionsctl list`

3. **Check Recent Logs**:
   ```bash
   # System extension logs
   log show --predicate 'subsystem == "com.apple.systemextensions"' --last 1h
   
   # USB/IP specific logs
   log show --predicate 'subsystem == "com.usbipd.mac"' --last 1h
   ```

4. **Include Build Information**:
   - Swift version: `swift --version`
   - Xcode version: `xcodebuild -version`
   - Build configuration and target platform

## Additional Resources

- [System Extension Development Guide](../development/system-extension-development.md) - Complete development documentation
- [Build Troubleshooting](build-troubleshooting.md) - General build issues
- [Apple Developer Documentation](https://developer.apple.com/documentation/systemextensions) - Official System Extension documentation
- [DriverKit Documentation](https://developer.apple.com/documentation/driverkit) - DriverKit development resources