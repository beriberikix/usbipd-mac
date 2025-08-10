# System Extension Installation and Configuration Guide

This document provides detailed instructions for building, installing, and configuring the USB/IP System Extension on macOS, including the new automated bundle creation process.

## Overview

The USB/IP System Extension provides exclusive access to USB devices, allowing them to be shared over IP networks using the USB/IP protocol. This System Extension is required for proper device claiming functionality.

### New in Version 2.0: Automated Bundle Creation

The latest version includes an automated System Extension bundle creation system that:
- Automatically generates .systemextension bundles during build
- Handles code signing and entitlements configuration
- Supports both development and distribution workflows
- Integrates with Swift Package Manager build plugins

## System Requirements

- **macOS 11.0** or later (Big Sur, Monterey, Ventura, Sonoma, Sequoia)
- **System Integrity Protection (SIP)** enabled (required for System Extensions)
- **Administrator privileges** for installation
- **Swift 5.9** or later (for building from source)
- **Xcode 15** or later (recommended for development)
- **Code signing certificate** (for distribution)
  - Developer ID Application certificate
  - Developer ID Kernel Extension certificate (for System Extensions)

## Building and Installation Process

### 1. Building the System Extension Bundle

The project now includes an automated bundle creation system using Swift Package Manager plugins.

#### Automated Build Process

Build the complete project with System Extension bundle:

```bash
# Build all targets including System Extension bundle
swift build --configuration release

# The bundle will be automatically created at:
# .build/release/SystemExtension.systemextension
```

The build process automatically:
1. Compiles the SystemExtension executable target
2. Creates the .systemextension bundle structure
3. Processes the Info.plist template with build-time variables
4. Copies entitlements and resources
5. Signs the bundle (if certificates are available)

#### Manual Bundle Creation (Development)

For development or custom builds:

```bash
# Build SystemExtension executable
swift build --product SystemExtension --configuration debug

# Bundle will be created by the SystemExtensionBundleBuilder plugin
# Location: .build/debug/SystemExtension.systemextension
```

#### Bundle Structure

The generated bundle follows the standard System Extension format:
```
SystemExtension.systemextension/
├── Contents/
│   ├── Info.plist                    # Bundle metadata
│   ├── MacOS/
│   │   └── SystemExtension           # Executable
│   └── Resources/
│       └── SystemExtension.entitlements
```

### 2. Development Mode Setup

For development and testing, enable System Extension development mode:

```bash
# Enable development mode (requires restart)
sudo systemextensionsctl developer on

# Verify development mode status
systemextensionsctl developer
```

Development mode allows:
- Installing unsigned System Extension bundles
- Loading extensions without notarization
- Enhanced debugging and logging capabilities

### 3. Code Signing Configuration

#### For Development

Development builds can use unsigned bundles when development mode is enabled:

```bash
# Check if development mode supports unsigned bundles
swift run usbipd --check-dev-mode

# Build unsigned bundle for development
swift build --configuration debug
```

#### For Distribution

Production builds require proper code signing:

```bash
# Set up environment variables for signing
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAM_ID)"
export SYSTEM_EXTENSION_IDENTITY="Developer ID Kernel Extension: Your Name (TEAM_ID)"

# Build signed bundle for distribution
swift build --configuration release
```

The build system will automatically detect available certificates and sign the bundle.

### 4. Installation Process

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

1. Build the System Extension bundle (see above)

2. Install the bundle manually:
   ```bash
   # For development (with development mode enabled)
   sudo systemextensionsctl install .build/debug/SystemExtension.systemextension

   # For distribution
   sudo systemextensionsctl install .build/release/SystemExtension.systemextension
   ```

3. Approve the System Extension in System Preferences when prompted

### 5. System Permission Approval

When the System Extension is first loaded, macOS will display system dialogs:

1. **System Extension Blocked** - Click "Open Security Preferences"
2. **Security & Privacy** - Click "Allow" next to the blocked extension
3. **System Extension Updated** - Click "Allow" if prompted for updates

### 6. Verification

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

## Development Workflow

### Development Environment Setup

1. **Enable Development Mode**:
   ```bash
   # Enable development mode (requires restart)
   sudo systemextensionsctl developer on
   
   # Verify development mode is enabled
   systemextensionsctl developer
   ```

2. **Configure Build Environment**:
   ```bash
   # Set development environment variable
   export SYSTEM_EXTENSION_DEVELOPMENT=1
   
   # Optional: Set custom signing identity
   export CODESIGN_IDENTITY="Mac Developer: Your Name (TEAM_ID)"
   ```

### Development Build Process

```bash
# Clean previous builds
swift package clean

# Build with debug configuration
swift build --configuration debug

# Verify bundle creation
ls -la .build/debug/SystemExtension.systemextension/

# Check bundle structure and signing
codesign -dv --verbose=4 .build/debug/SystemExtension.systemextension
```

### Development Testing

```bash
# Run unit tests
swift test

# Run System Extension integration tests
swift test --filter SystemExtensionIntegrationTests

# Run installation-specific tests
swift test --filter SystemExtensionInstallationTests

# Test bundle validation
swift run usbipd --validate-bundle .build/debug/SystemExtension.systemextension
```

### Development Debugging

```bash
# Monitor System Extension logs in real-time
log stream --predicate 'subsystem == "com.github.usbipd-mac"'

# Check bundle validation
swift run usbipd --check-dev-mode

# Test installation workflow
swift run usbipd --test-install-dev

# Verbose daemon with extension debugging
sudo swift run usbipd daemon --verbose --debug-extension
```

### Bundle Validation Tools

The project includes built-in validation tools:

```bash
# Validate bundle structure
swift run SystemExtensionBundleValidator .build/debug/SystemExtension.systemextension

# Check development mode compatibility  
swift run DevelopmentModeChecker

# Validate entitlements and signing
swift run BundleValidator --check-signing --check-entitlements
```

### Common Development Tasks

```bash
# Quick development cycle
make dev-build      # Build, install, and test in development mode
make dev-test       # Run all development tests
make dev-clean      # Clean and reset development environment

# Manual development workflow
swift build --configuration debug
sudo systemextensionsctl install .build/debug/SystemExtension.systemextension
usbipd status --health
```

### Development Troubleshooting

#### Bundle Creation Issues

```bash
# Check plugin execution
swift build --verbose

# Validate bundle manually
find .build/debug -name "*.systemextension" -exec ls -la {} \;

# Check bundle contents
unzip -l .build/debug/SystemExtension.systemextension/Contents/Info.plist
```

#### Installation Issues in Development Mode

```bash
# Verify development mode
systemextensionsctl developer

# Check extension staging
ls -la /Library/SystemExtensions/

# Reset development environment
sudo systemextensionsctl reset
sudo systemextensionsctl developer on
# (restart required)
```

### Testing and Validation

```bash
# Comprehensive test suite
swift test --parallel --verbose

# Integration tests with real devices
swift test --filter SystemExtensionIntegrationTests

# Installation workflow tests
swift test --filter SystemExtensionInstallationTests

# Development mode specific tests
swift test --filter DevelopmentModeTests

# Performance and stress tests
swift test --filter SystemExtensionPerformanceTests
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

- **2.0.0**: System Extension Bundle Creation (Current)
  - Automated System Extension bundle creation via Swift Package Manager plugins
  - Development mode support with unsigned bundle handling
  - Enhanced error handling and troubleshooting capabilities
  - Comprehensive integration tests for installation workflows
  - Bundle validation and development tools
  - Improved code signing and entitlements management

- **1.0.0**: Initial System Extension implementation
  - USB device claiming and release functionality
  - IPC communication with main daemon
  - Health monitoring and status reporting
  - Integration with CLI commands

## Additional Resources

### Swift Package Manager Integration

The System Extension bundle creation is fully integrated with Swift Package Manager:

- **Plugin System**: Uses buildToolPlugins for automated bundle creation
- **Target Configuration**: SystemExtension target automatically builds as executable
- **Dependency Management**: Proper dependency resolution for System Extension components
- **Build Caching**: Efficient incremental builds with proper dependency tracking

### Build System Architecture

```
Package.swift
├── SystemExtension (executableTarget)
│   ├── Sources/SystemExtension/main.swift
│   └── Dependencies: [USBIPDCore, Common]
├── SystemExtensionBundleBuilder (buildToolPlugin)
│   ├── BundleBuilder.swift
│   ├── CodeSigning.swift
│   └── BundleValidator.swift
└── Build Output
    └── .build/{configuration}/SystemExtension.systemextension/
```

### Continuous Integration

For CI/CD pipelines, the build system supports:

```bash
# CI build with validation
swift build --configuration release
swift test --parallel

# Verify bundle creation
test -d .build/release/SystemExtension.systemextension

# Validate bundle structure (CI-safe)
swift run BundleValidator --ci-mode .build/release/SystemExtension.systemextension
```