# usbipd-mac

A macOS implementation of the USB/IP protocol that allows sharing USB devices over IP networks.

## Overview

usbipd-mac is a macOS implementation of the USB/IP protocol that allows sharing USB devices over IP networks. This server implementation enables macOS users to share USB devices with any compatible USB/IP client, with a focus on compatibility with the Linux Kernel virtual HCI driver (vhci-hcd.ko). Docker support on macOS is also a goal.

## Features

- USB device sharing from macOS to other systems over network
- Full compatibility with the USB/IP protocol specification
- System Extensions integration for reliable device access and claiming
- Automated System Extension bundle creation and deployment
- Lightweight QEMU test server for validation
- Docker enablement for USB device access from containers

## Requirements

- **macOS 11.0+**: System Extensions are only supported on macOS Big Sur and later
- **Xcode 13+**: Required for System Extensions support and Swift Package Manager
- **Code Signing**: Optional for development, required for distribution

## Project Status

This project is currently in early development. The core server functionality is being implemented as an MVP.

## Building the Project

### Quick Start

```bash
# Build the project
swift build

# Build with Xcode (recommended for development)
xcodebuild -scheme usbipd-mac build
```

### System Extension Development

For development with System Extensions:

```bash
# Enable System Extension development mode (requires reboot)
sudo systemextensionsctl developer on

# Build and install for development
swift build
sudo usbipd daemon --install-extension

# Check status
usbipd status
```

## Running Tests

```bash
# Run all tests
swift test

# Run specific test environments (see Documentation for details)
./Scripts/run-development-tests.sh    # Fast development tests
./Scripts/run-ci-tests.sh             # CI-compatible tests  
./Scripts/run-production-tests.sh     # Comprehensive validation
```

## Documentation

For detailed information about development, architecture, and troubleshooting, see the comprehensive documentation in the [`Documentation/`](Documentation/) folder:

### Development Documentation
- [**Architecture**](Documentation/development/architecture.md) - System design and component overview
- [**CI/CD Pipeline**](Documentation/development/ci-cd.md) - Continuous integration and branch protection
- [**System Extension Development**](Documentation/development/system-extension-development.md) - System Extension setup and development
- [**Testing Strategy**](Documentation/development/testing-strategy.md) - Test environments and validation approaches

### API and Protocol Documentation
- [**USB Implementation**](Documentation/api/usb-implementation.md) - USB/IP protocol implementation details
- [**Protocol Reference**](Documentation/protocol-reference.md) - USB/IP protocol specification
- [**QEMU Test Tool**](Documentation/qemu-test-tool.md) - QEMU validation server usage

### Troubleshooting Guides
- [**Build Troubleshooting**](Documentation/troubleshooting/build-troubleshooting.md) - Common build and setup issues
- [**System Extension Troubleshooting**](Documentation/troubleshooting/system-extension-troubleshooting.md) - System Extension specific problems
- [**QEMU Troubleshooting**](Documentation/troubleshooting/qemu-troubleshooting.md) - QEMU test server issues

## License

[MIT License](LICENSE)