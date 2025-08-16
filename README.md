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

## Installation

### Homebrew Installation (Recommended)

The easiest way to install usbipd-mac is through Homebrew:

```bash
# Add the usbipd-mac tap
brew tap beriberikix/usbipd-mac

# Install usbipd-mac
brew install usbipd-mac
```

#### Service Management

After installation, you can manage the usbipd daemon using Homebrew services:

```bash
# Start the service (requires sudo for System Extension access)
sudo brew services start usbipd-mac

# Stop the service
sudo brew services stop usbipd-mac

# Restart the service
sudo brew services restart usbipd-mac

# Check service status
brew services info usbipd-mac
```

#### System Extension Setup

After Homebrew installation, you'll need to approve the System Extension:

1. **System Extension Approval**: macOS will prompt you to approve the System Extension in **System Preferences > Security & Privacy > General**
2. **Restart Required**: A restart may be required for the System Extension to become active
3. **Verification**: Check the System Extension status with `usbipd status`

#### Troubleshooting Homebrew Installation

Common installation issues and solutions:

- **Permission Errors**: Ensure you run service commands with `sudo` as the daemon requires System Extension privileges
- **System Extension Blocked**: Check System Preferences > Security & Privacy and approve the extension
- **Service Won't Start**: Verify the binary installed correctly with `which usbipd` and check logs with `brew services list`
- **Version Issues**: Update with `brew upgrade usbipd-mac` or reinstall with `brew reinstall usbipd-mac`

### Manual Installation (Development)

For development or manual installation, see the [Building the Project](#building-the-project) section below.

## Usage

Once installed, you can use usbipd-mac to share USB devices over the network:

### Basic Commands

```bash
# List available USB devices
usbipd list

# Share a USB device (device ID from list command)
usbipd bind --device <device-id>

# Check daemon status and shared devices
usbipd status

# Stop sharing a device
usbipd unbind --device <device-id>
```

### Client Connection

From a USB/IP client (typically Linux):

```bash
# Install USB/IP tools (Ubuntu/Debian)
sudo apt install linux-tools-generic

# Connect to shared device
sudo usbip attach -r <macos-ip-address> -b <device-id>

# List attached devices
usbip port

# Detach device
sudo usbip detach -p <port-number>
```

### Docker Integration

For Docker Desktop users:

```bash
# Ensure the service is running
sudo brew services start usbipd-mac

# USB devices will be available to Docker containers
# through the USB/IP protocol integration
```

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
- [**Homebrew Troubleshooting**](Documentation/homebrew-troubleshooting.md) - Homebrew installation and service issues
- [**QEMU Troubleshooting**](Documentation/troubleshooting/qemu-troubleshooting.md) - QEMU test server issues

## Release Automation

usbipd-mac uses automated GitHub Actions workflows for consistent and reliable releases.

### For Maintainers

#### Release Process

1. **Prepare Release**:
   ```bash
   # Run local release preparation
   ./Scripts/prepare-release.sh <version>
   
   # This will:
   # - Validate environment and dependencies
   # - Run comprehensive test suite
   # - Generate changelog entries
   # - Create and push version tag
   ```

2. **Automated Pipeline**: Once a version tag is pushed, GitHub Actions automatically:
   - Validates the release candidate
   - Builds production artifacts with code signing
   - Runs comprehensive test validation
   - Publishes release with checksums and signatures
   - Updates documentation and notifications

3. **Emergency Releases**: For critical fixes, use the manual workflow dispatch in GitHub Actions with validation bypasses as documented in [Emergency Release Procedures](Documentation/Emergency-Release-Procedures.md).

#### Versioning Strategy

- **Semantic Versioning**: Follow semver (MAJOR.MINOR.PATCH) for all releases
- **Release Schedule**: Monthly minor releases with patch releases as needed
- **Pre-releases**: Use `-alpha`, `-beta`, `-rc` suffixes for testing releases
- **Changelog**: Automatically generated from conventional commits

#### Required Setup

For release automation to work properly:

1. **Code Signing**: Configure Apple Developer certificates in GitHub repository secrets
2. **Permissions**: Ensure maintainer access to repository settings and secrets
3. **Environment**: Validate local environment with `./Scripts/prepare-release.sh --check`

See [Release Automation Documentation](Documentation/Release-Automation.md) for complete setup instructions and troubleshooting.

### For Contributors

Release automation is handled by maintainers. Contributors should:
- Follow conventional commit format for automatic changelog generation
- Ensure all PRs pass CI validation before merge
- Report issues with release automation to repository maintainers

## License

[MIT License](LICENSE)