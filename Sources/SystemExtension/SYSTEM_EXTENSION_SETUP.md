# System Extension Installation and Configuration Guide

This document provides detailed instructions for installing and configuring the USB/IP System Extension on macOS.

## Overview

The USB/IP System Extension provides exclusive access to USB devices, allowing them to be shared over IP networks using the USB/IP protocol. This System Extension is required for proper device claiming functionality.

## System Requirements

- **macOS 11.0** or later (Big Sur, Monterey, Ventura, Sonoma, Sequoia)
- **System Integrity Protection (SIP)** enabled (required for System Extensions)
- **Administrator privileges** for installation
- **Code signing certificate** (for distribution)

## Installation Process

### 1. Pre-Installation Requirements

Before installing the System Extension, ensure that:

- System Integrity Protection (SIP) is enabled
- The main USB/IP daemon is not currently running
- You have administrator privileges on the system

Check SIP status:
```bash
csrutil status
```

### 2. System Extension Installation

#### Option A: Automatic Installation (Recommended)

The System Extension will be automatically installed when first needed:

1. Run the USB/IP daemon:
   ```bash
   sudo usbipd daemon
   ```

2. Attempt to bind a device:
   ```bash
   usbipd bind 1-1
   ```

3. The system will prompt for System Extension installation approval.

#### Option B: Manual Installation

1. Build the project with System Extension target:
   ```bash
   swift build --configuration release
   ```

2. Copy the System Extension bundle to the appropriate location
3. Load the System Extension using `systemextensionsctl`

### 3. System Permission Approval

When the System Extension is first loaded, macOS will display system dialogs:

1. **System Extension Blocked** - Click "Open Security Preferences"
2. **Security & Privacy** - Click "Allow" next to the blocked extension
3. **System Extension Updated** - Click "Allow" if prompted for updates

### 4. Verification

Verify the System Extension is loaded and running:

```bash
# Check system extension status
systemextensionsctl list

# Check USB/IP system status
usbipd status

# Verify with detailed health check
usbipd status --health
```

Expected output should show:
- System Extension status: Running ✅
- Health check: Passed ✅
- No critical errors

## Configuration Details

### Bundle Information

- **Bundle Identifier**: `com.usbipd.mac.system-extension`
- **Extension Point**: `com.apple.system-extension.driver-extension`
- **Principal Class**: `SystemExtensionManager`
- **Version**: 1.0.0

### Required Entitlements

The System Extension requires the following entitlements:

- `com.apple.developer.driverkit` - DriverKit development
- `com.apple.developer.driverkit.usb.transport` - USB transport access
- `com.apple.developer.driverkit.allow-any-userclient-access` - User client access
- `com.apple.developer.system-extension.install` - System Extension installation
- `com.apple.security.device.usb` - USB device access
- `com.apple.developer.system-extension.request` - Extension request capability

### IOKit Personalities

The extension includes IOKit personalities for USB device matching:

- **IOClass**: IOUserService
- **IOMatchCategory**: USBIPDSystemExtension
- **IOUserClass**: SystemExtensionManager

## Troubleshooting

### Common Issues

#### 1. System Extension Installation Fails

**Symptoms**: Extension installation is blocked or fails silently

**Solutions**:
- Ensure SIP is enabled: `csrutil status`
- Check System Preferences > Security & Privacy for blocked extensions
- Restart the system and try again
- Check Console.app for system extension logs

#### 2. Permission Denied Errors

**Symptoms**: USB device access is denied

**Solutions**:
- Verify the extension is properly loaded: `systemextensionsctl list`
- Check entitlements are properly configured
- Ensure the application is code-signed with proper provisioning
- Run with administrator privileges if necessary

#### 3. Device Claiming Fails

**Symptoms**: Devices cannot be claimed for USB/IP sharing

**Solutions**:
- Check system extension health: `usbipd status --health`
- Verify USB device is not in use by another application
- Check system logs for IOKit errors
- Try unbinding and rebinding the device

#### 4. Extension Not Loading

**Symptoms**: System Extension appears inactive or not loaded

**Solutions**:
- Check extension permissions in Security & Privacy preferences
- Verify bundle identifier and code signing
- Try manual loading: `systemextensionsctl developer on`
- Check system extension staging area: `/Library/SystemExtensions/`

### Debug Commands

```bash
# List all system extensions
systemextensionsctl list

# Check system extension logs
log show --predicate 'subsystem == "com.apple.systemextensions"' --last 1h

# Check USB/IP daemon logs
log show --predicate 'subsystem == "com.usbipd.mac"' --last 1h

# Enable developer mode for extensions (development only)
systemextensionsctl developer on

# Reset system extensions (development only - use with caution)
systemextensionsctl reset
```

### Log Analysis

Monitor logs in real-time during installation:

```bash
# System extension management logs
log stream --predicate 'subsystem == "com.apple.systemextensions"'

# USB/IP specific logs
log stream --predicate 'subsystem == "com.usbipd.mac"'

# IOKit and USB-related logs
log stream --predicate 'category == "USB"'
```

## Security Considerations

### Code Signing Requirements

For distribution, the System Extension must be properly code-signed:

- **Developer ID Application** certificate for the main application
- **Developer ID Kernel Extension** certificate for the System Extension
- **Notarization** through Apple's notary service

### Permissions Model

The System Extension operates with restricted permissions:

- **USB Device Access**: Limited to devices explicitly bound through the CLI
- **Network Access**: Only for USB/IP protocol communication
- **System Access**: Minimal required privileges for USB device claiming

### Privacy Protection

- No user data collection or transmission
- USB device metadata is only processed locally
- Network communication limited to USB/IP protocol data

## Development Notes

### Building for Development

```bash
# Build with development certificates
swift build --configuration debug

# Enable development mode for testing
sudo systemextensionsctl developer on

# Install development extension
sudo systemextensionsctl install path/to/extension
```

### Testing and Validation

```bash
# Run comprehensive integration tests
swift test --filter SystemExtensionIntegrationTests

# Test with real USB devices
usbipd list
usbipd bind <device-id>
usbipd status --detailed
```

## Support and Maintenance

### Update Process

System Extensions are updated automatically with the main application:

1. Install updated USB/IP daemon
2. System Extension will be updated on next use
3. User approval may be required for updates

### Uninstallation

To remove the System Extension:

```bash
# Stop the daemon
sudo pkill usbipd

# Deactivate the extension
systemextensionsctl deactivate com.usbipd.mac.system-extension

# Remove application bundle
rm -rf /Applications/usbipd.app
```

### Getting Help

- Check system logs for detailed error messages
- Use `usbipd status --detailed` for diagnostic information
- Review this documentation for common solutions
- File issues with detailed logs and system information

## Version History

- **1.0.0**: Initial System Extension implementation
  - USB device claiming and release functionality
  - IPC communication with main daemon
  - Health monitoring and status reporting
  - Integration with CLI commands