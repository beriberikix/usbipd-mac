# System Extension Installation and Configuration Guide

This document provides detailed instructions for building, installing, and configuring the USB/IP System Extension on macOS using the new automated workflow system.

## Overview

The USB/IP System Extension provides exclusive access to USB devices, allowing them to be shared over IP networks using the USB/IP protocol. This System Extension is required for proper device claiming functionality.

### New Shell Script-Based Workflow

The latest version includes a comprehensive shell script-based System Extension workflow that:
- Automates development environment setup and validation
- Handles System Extension bundle creation with proper structure
- Manages code signing and certificate detection automatically
- Provides complete installation and status monitoring
- Supports both development and distribution workflows
- Maintains Linux CLI compatibility by using shell scripts instead of extending the CLI

## System Requirements

- **macOS 11.0** or later (Big Sur, Monterey, Ventura, Sonoma, Sequoia)
- **System Integrity Protection (SIP)** enabled (required for System Extensions)
- **Administrator privileges** for installation
- **Swift 5.9** or later (for building from source)
- **Xcode 15** or later (recommended for development)
- **Code signing certificate** (for distribution)
  - Developer ID Application certificate
  - Developer ID Kernel Extension certificate (for System Extensions)

## Quick Start

### 1. Development Environment Setup

Set up your development environment with a single command:

```bash
# Automated development environment setup
./Scripts/setup-dev-environment.sh
```

This script will:
- Check macOS system requirements and SIP status
- Verify Xcode Command Line Tools installation
- Detect available development certificates
- Configure developer mode settings
- Build the project if needed

### 2. Install System Extension

Install the System Extension with automated bundle creation:

```bash
# Complete installation workflow (build + create bundle + sign + install)
./Scripts/install-extension.sh

# For development (skip code signing)
./Scripts/install-extension.sh --skip-signing

# Force reinstall with verbose output
./Scripts/install-extension.sh --force --verbose
```

### 3. Check Status

Monitor System Extension status:

```bash
# Basic status check
./Scripts/extension-status.sh

# Comprehensive health check
./Scripts/extension-status.sh --health --verbose

# Watch status changes in real-time
./Scripts/extension-status.sh --watch
```

## Detailed Installation Process

### 1. Building the Project

The shell script workflow builds the project as needed:

```bash
# Manual build (done automatically by installation script)
swift build --configuration debug

# Release build for distribution
swift build --configuration release
```

The build creates the SystemExtension executable that will be bundled into the .systemextension package.

### 2. Bundle Creation

System Extension bundles are created automatically during installation:

```bash
# Bundle creation is handled by install-extension.sh
# Manual bundle validation
./Scripts/validate-bundle.sh

# Deep validation with detailed checks
./Scripts/validate-bundle.sh --deep --verbose
```

#### Bundle Structure

The generated bundle follows the standard System Extension format:
```
USBIPDSystemExtension.systemextension/
├── Contents/
│   ├── Info.plist                    # Bundle metadata and configuration
│   ├── MacOS/
│   │   └── USBIPDSystemExtension     # Compiled executable
│   └── Resources/
│       └── (entitlements and resources as needed)
```

### 3. Development Mode Setup

The setup script automatically handles development mode configuration:

```bash
# Automated setup includes development mode checks
./Scripts/setup-dev-environment.sh

# Check only development mode status
./Scripts/setup-dev-environment.sh --check-sip

# Manual development mode setup (if needed)
sudo systemextensionsctl developer on
# (restart required)

# Verify development mode status
systemextensionsctl developer
```

Development mode allows:
- Installing unsigned System Extension bundles
- Loading extensions without notarization
- Enhanced debugging and logging capabilities

### 4. Code Signing Configuration

The installation script automatically handles code signing:

#### For Development

Development builds can use unsigned bundles when development mode is enabled:

```bash
# Check available certificates
./Scripts/setup-dev-environment.sh --check-certs

# Install with unsigned bundle (development mode)
./Scripts/install-extension.sh --skip-signing
```

#### For Distribution

Production builds require proper code signing:

```bash
# The script automatically detects available certificates:
# - Developer ID Application certificates
# - Mac Developer certificates
# - Handles certificate selection and signing

# Install with automatic signing
./Scripts/install-extension.sh

# Verify bundle signature
./Scripts/validate-bundle.sh --deep
```

The installation script will automatically detect available certificates and sign the bundle appropriately.

### 5. Installation Process

#### Option A: Automated Script Installation (Recommended)

Use the comprehensive installation script:

```bash
# Complete automated workflow
./Scripts/install-extension.sh

# Installation with options
./Scripts/install-extension.sh --force --verbose

# Development installation (unsigned)
./Scripts/install-extension.sh --skip-signing
```

The script automatically:
1. Builds the project if needed
2. Creates the System Extension bundle
3. Signs the bundle (if certificates available)
4. Installs the System Extension
5. Verifies the installation

#### Option B: Manual Installation

For advanced users or troubleshooting:

```bash
# 1. Build the project
swift build --configuration debug

# 2. Create and validate bundle manually
./Scripts/validate-bundle.sh

# 3. Install bundle manually
sudo systemextensionsctl install .build/USBIPDSystemExtension.systemextension

# 4. Check installation status
./Scripts/extension-status.sh
```

#### Option C: Runtime Installation

The System Extension can also be installed automatically when first needed:

1. Run the USB/IP daemon:
   ```bash
   sudo usbipd daemon
   ```

2. Attempt to bind a device:
   ```bash
   usbipd bind 1-1
   ```

3. The system will prompt for System Extension installation approval.

### 6. System Permission Approval

When the System Extension is first loaded, macOS will display system dialogs:

1. **System Extension Blocked** - Click "Open Security Preferences"
2. **Security & Privacy** - Click "Allow" next to the blocked extension
3. **System Extension Updated** - Click "Allow" if prompted for updates

### 7. Verification

Verify the System Extension is loaded and running:

```bash
# Comprehensive status check
./Scripts/extension-status.sh

# Detailed health check
./Scripts/extension-status.sh --health --verbose

# Watch status in real-time
./Scripts/extension-status.sh --watch

# System-level verification
systemextensionsctl list

# Check USB/IP system status (if CLI supports it)
usbipd status
```

Expected output should show:
- System Extension status: `[activated enabled]` ✅
- Health check: No critical errors ✅
- Bundle validation: Passed ✅

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

The new diagnostic system provides comprehensive troubleshooting capabilities:

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

### Common Issues

#### 1. System Extension Installation Fails

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

#### 2. Permission Denied Errors

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

#### 3. Device Claiming Fails

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

#### 4. Extension Not Loading

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

### Debug Commands

The new shell script system provides comprehensive debugging tools:

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

### Streamlined Development Setup

The new shell script-based workflow provides a streamlined development experience:

```bash
# Complete development environment setup
./Scripts/setup-dev-environment.sh

# Development build and install cycle
./Scripts/install-extension.sh --skip-signing --verbose

# Monitor development status
./Scripts/extension-status.sh --watch
```

### Development Environment Setup

1. **Automated Environment Setup**:
   ```bash
   # Complete setup with interactive guidance
   ./Scripts/setup-dev-environment.sh
   
   # Validation only
   ./Scripts/setup-dev-environment.sh --validate
   
   # Check specific components
   ./Scripts/setup-dev-environment.sh --check-sip
   ./Scripts/setup-dev-environment.sh --check-certs
   ```

2. **Manual Development Mode (if needed)**:
   ```bash
   # Enable development mode (requires restart)
   sudo systemextensionsctl developer on
   
   # Verify development mode is enabled
   systemextensionsctl developer
   ```

### Development Build Process

```bash
# Clean development build
swift package clean
swift build --configuration debug

# Automated build with bundle creation
./Scripts/install-extension.sh --dry-run  # See what would be done
./Scripts/install-extension.sh --skip-signing  # Development install

# Validate the created bundle
./Scripts/validate-bundle.sh --deep --verbose
```

### Development Testing

```bash
# Run unit tests
swift test --parallel --verbose

# Run System Extension integration tests
swift test --filter SystemExtensionIntegrationTests

# Run installation-specific tests
swift test --filter SystemExtensionInstallationTests

# Test bundle validation
./Scripts/validate-bundle.sh --deep
```

### Development Debugging

```bash
# Real-time status monitoring
./Scripts/extension-status.sh --watch

# Comprehensive debugging
./Scripts/extension-status.sh --health --verbose --logs

# Bundle validation
./Scripts/validate-bundle.sh --deep --verbose

# Environment validation
./Scripts/setup-dev-environment.sh --validate
```

### Development Tools Integration

The shell scripts provide comprehensive development tools:

```bash
# Bundle structure validation
./Scripts/validate-bundle.sh

# Environment compatibility check
./Scripts/setup-dev-environment.sh --validate

# Status monitoring with JSON output for integration
./Scripts/extension-status.sh --json

# Comprehensive health checks
./Scripts/extension-status.sh --health
```

### Common Development Tasks

```bash
# Quick development cycle
./Scripts/setup-dev-environment.sh         # One-time setup
./Scripts/install-extension.sh --skip-signing    # Development install
./Scripts/extension-status.sh --health     # Verify installation

# Rebuild and reinstall workflow
./Scripts/install-extension.sh --force --skip-signing --verbose

# Clean development environment
swift package clean
sudo systemextensionsctl reset  # Nuclear option
./Scripts/setup-dev-environment.sh
```

### Development Troubleshooting

#### Bundle Creation Issues

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

#### Installation Issues in Development Mode

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

### Testing and Validation

```bash
# Comprehensive test suite
swift test --parallel --verbose

# Integration tests with real devices
swift test --filter SystemExtensionIntegrationTests

# Installation workflow tests
swift test --filter SystemExtensionInstallationTests

# Bundle validation tests
./Scripts/validate-bundle.sh --deep

# Environment validation tests
./Scripts/setup-dev-environment.sh --validate

# End-to-end workflow testing
./Scripts/install-extension.sh --dry-run --verbose
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

- **2.0.0**: Shell Script-Based Workflow System (Current)
  - Comprehensive shell script-based installation workflow replacing broken plugin system
  - Automated development environment setup and validation (`setup-dev-environment.sh`)
  - Complete System Extension installation workflow (`install-extension.sh`)
  - Real-time status monitoring and health checking (`extension-status.sh`)
  - Bundle validation and integrity checking (`validate-bundle.sh`)
  - Automated certificate detection and code signing management
  - Linux CLI compatibility through shell scripts instead of CLI extensions
  - Enhanced error handling and troubleshooting capabilities
  - Comprehensive integration tests for installation workflows
  - Post-build integration script for build system compatibility

- **1.0.0**: Initial System Extension implementation
  - USB device claiming and release functionality
  - IPC communication with main daemon
  - Health monitoring and status reporting
  - Integration with CLI commands

## Additional Resources

### Shell Script Integration

The System Extension workflow is fully integrated through shell scripts:

- **Environment Setup**: `setup-dev-environment.sh` provides comprehensive environment validation
- **Installation Workflow**: `install-extension.sh` handles complete build-to-install pipeline
- **Status Monitoring**: `extension-status.sh` provides real-time monitoring and health checks
- **Bundle Validation**: `validate-bundle.sh` ensures bundle integrity and structure
- **Linux Compatibility**: Shell scripts maintain CLI compatibility across platforms

### Workflow Architecture

```
Scripts/
├── setup-dev-environment.sh     # Environment setup and validation
├── install-extension.sh         # Complete installation workflow
├── extension-status.sh          # Status monitoring and health checks  
├── validate-bundle.sh           # Bundle validation and integrity
└── post-build-extension.sh      # Build system integration

Integration Points:
├── Swift Package Manager (builds executables)
├── SystemExtensionBundleCreator (creates bundles)
├── CodeSigningManager (handles signing)
├── SystemExtensionInstaller (installation)
└── SystemExtensionDiagnostics (health monitoring)
```

### Continuous Integration

For CI/CD pipelines, the shell script system supports:

```bash
# CI build with validation
swift build --configuration release
swift test --parallel

# Environment validation (CI-safe)
./Scripts/setup-dev-environment.sh --validate

# Bundle validation (without installation)  
./Scripts/validate-bundle.sh --json

# Complete workflow testing (dry-run)
./Scripts/install-extension.sh --dry-run --verbose
```

### Integration with External Tools

```bash
# JSON output for automation
./Scripts/extension-status.sh --json > status.json
./Scripts/validate-bundle.sh --json > validation.json

# Health monitoring integration
./Scripts/extension-status.sh --health --quiet  # Exit codes for scripting

# Automated workflows
./Scripts/setup-dev-environment.sh --validate --quiet && \
./Scripts/install-extension.sh --skip-signing && \
./Scripts/extension-status.sh --health
```