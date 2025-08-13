# System Architecture

This document provides a comprehensive overview of the usbipd-mac system architecture, covering component design, System Extension integration, and technical decisions.

## Overview

usbipd-mac is a macOS implementation of the USB/IP protocol that allows sharing USB devices over IP networks. The system architecture is designed around modern macOS security requirements, utilizing System Extensions for secure USB device access while maintaining compatibility with existing USB/IP clients.

## Core Architecture Components

### Component Overview

The project is structured as a multi-target Swift package with clear separation of concerns:

- **USBIPDCore**: Core USB/IP protocol implementation and device management
- **USBIPDCLI**: Command-line interface executable (`usbipd` binary)
- **Common**: Shared utilities (logging, error handling)
- **SystemExtension**: macOS System Extension integration
- **QEMUTestServer**: QEMU validation test server

### System Extension Bundle Architecture

This project includes full System Extension bundle support for secure USB device access on macOS. System Extensions provide a modern, secure way to access USB devices without requiring kernel extensions.

#### Requirements

- **macOS 11.0+**: System Extensions are only supported on macOS Big Sur and later
- **Code Signing**: System Extension bundles require valid Developer ID or development certificates
- **User Approval**: First-time installation requires user approval in System Preferences

#### System Extension Bundle Creation

The build system automatically creates System Extension bundles during compilation:

```bash
# Build creates SystemExtension.systemextension bundle automatically
swift build

# The bundle is created at:
# .build/[arch]-apple-macosx/debug/SystemExtension.systemextension/
```

#### Bundle Structure

The generated System Extension bundle includes:

```
SystemExtension.systemextension/
├── Contents/
│   ├── Info.plist              # Bundle metadata and entitlements
│   ├── MacOS/
│   │   └── SystemExtension     # System Extension executable
│   └── Resources/
│       └── SystemExtension.entitlements
```

## Installation and Activation Architecture

### Development Mode

For development and testing, the system supports System Extension development mode:

```bash
# Enable developer mode (requires reboot)
systemextensionsctl developer on

# Reset System Extensions if needed
systemextensionsctl reset
```

### Production Installation

System Extensions are installed automatically when the USB/IP daemon starts:

```bash
# Install and activate System Extension
sudo usbipd daemon --install-extension

# Check System Extension status
usbipd status
```

## Build Architecture

### Build System Integration

The build system is designed to handle multiple products and automatic bundle creation:

#### Build Commands

```bash
# Build using Swift Package Manager (creates System Extension bundle automatically)
swift build

# Build using Xcode (recommended for development)
xcodebuild -scheme usbipd-mac build

# Build specific products
swift build --product usbipd              # CLI executable
swift build --product SystemExtension     # System Extension executable
swift build --product QEMUTestServer      # Test server
```

#### Build Artifacts

After building, the following artifacts are created:

```
.build/[arch]-apple-macosx/debug/
├── usbipd                                      # Main CLI executable
├── SystemExtension                             # System Extension executable
├── SystemExtension.systemextension/            # Complete System Extension bundle
│   ├── Contents/
│   │   ├── Info.plist
│   │   │   ├── MacOS/SystemExtension
│   │   └── Resources/SystemExtension.entitlements
└── QEMUTestServer                              # Test validation server
```

### Development Build Setup

For development with System Extensions:

```bash
# Enable System Extension development mode
sudo systemextensionsctl developer on

# Build and install for development
swift build
sudo usbipd daemon --install-extension

# Verify installation
usbipd status
systemextensionsctl list
```

## Security Architecture

### Code Signing Requirements

- **Development**: Use Xcode automatic signing
- **Production**: Valid Developer ID certificate
- **System Extensions**: Require valid code signing for installation and execution

### Permission Model

System Extensions operate with restricted permissions:
- User approval required for first-time installation
- Sandboxed execution environment
- Entitlements-based capability model
- Secure communication with hosting application

## Error Handling and Diagnostics

### System Extension Diagnostics

The architecture includes comprehensive diagnostic capabilities:

```bash
# Verify bundle exists
ls -la .build/arm64-apple-macosx/debug/SystemExtension.systemextension

# Check bundle signature
codesign -v .build/arm64-apple-macosx/debug/SystemExtension.systemextension

# View System Extension status
systemextensionsctl list
```

### Advanced Diagnostics

For complex System Extension issues:

1. **Reset System Extensions**: `systemextensionsctl reset` (requires reboot)
2. **Check System Integrity**: `sudo spctl --assess --type install [bundle-path]`
3. **Verify Code Signing**: `codesign -dv --verbose=4 [bundle-path]`
4. **System Extension Logs**: Use Console.app and filter for "systemextensionsd"

## Communication Architecture

### Protocol Layer

The system implements the complete USB/IP protocol specification for compatibility with existing clients, particularly targeting Linux Kernel virtual HCI driver (vhci-hcd.ko) compatibility.

### Network Communication

- TCP-based communication for USB/IP protocol
- Client-server architecture supporting multiple concurrent connections
- QEMU test server for validation and testing

## Development Architecture

### Prerequisites

- **Xcode 13+**: Required for System Extensions support and Swift Package Manager
- **macOS 11.0+ SDK**: System Extensions require macOS Big Sur SDK or later  
- **Code Signing**: Optional for development, required for distribution

## Integration Testing Architecture

### System Extension Testing

Testing System Extension functionality requires special setup:

```bash
# Enable development mode for testing
sudo systemextensionsctl developer on

# Run System Extension integration tests
swift test --filter SystemExtensionInstallationTests

# Test bundle creation and validation
swift test --filter BuildOutputVerificationTests

# Manual System Extension testing
usbipd status                    # Check System Extension status
usbipd status --detailed         # Detailed health information
usbipd status --health           # Health check only
```

This architecture ensures secure, reliable USB device sharing while maintaining compatibility with existing USB/IP infrastructure and adhering to modern macOS security requirements.