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

After Homebrew installation, you'll need to install and approve the System Extension:

1. **Automatic Installation**: Use the built-in installation command:
   ```bash
   # Install and register the System Extension (requires sudo)
   sudo usbipd install-system-extension
   ```

2. **System Extension Approval**: macOS will prompt you to approve the System Extension in **System Preferences > Security & Privacy > General**
3. **Restart Required**: A restart may be required for the System Extension to become active
4. **Verification**: Check the System Extension status with `usbipd status`

**Installation Diagnostics**: If you encounter issues, run comprehensive diagnostics:
```bash
# Run complete installation diagnostics
usbipd diagnose

# Run verbose diagnostics for detailed troubleshooting
usbipd diagnose --verbose
```

#### Troubleshooting Homebrew Installation

Common installation issues and solutions:

- **Permission Errors**: Ensure you run service commands with `sudo` as the daemon requires System Extension privileges
- **System Extension Blocked**: Check System Preferences > Security & Privacy and approve the extension
- **Service Won't Start**: Verify the binary installed correctly with `which usbipd` and check logs with `brew services list`
- **Version Issues**: Update with `brew upgrade usbipd-mac` or reinstall with `brew reinstall usbipd-mac`

#### System Extension Installation Troubleshooting

For System Extension specific issues:

**Installation Problems**:
- **Bundle Not Found**: Ensure Homebrew installation completed successfully, reinstall if needed
- **Registration Failed**: Run `sudo usbipd install-system-extension --verbose` for detailed error information
- **User Approval Required**: System Extensions require explicit user approval in System Preferences
- **Developer Mode Required**: For unsigned builds, enable developer mode: `sudo systemextensionsctl developer on`

**Common Error Solutions**:
```bash
# Check detailed installation status
usbipd diagnose --verbose

# Re-install System Extension if corrupted
sudo usbipd install-system-extension --skip-verification

# Verify System Extension is properly registered
systemextensionsctl list

# Check System Extension process status
usbipd status
```

**System Requirements**:
- **macOS 11.0+**: System Extensions are only available on Big Sur and later
- **Code Signing**: Production releases require properly signed System Extensions
- **System Integrity Protection**: Must be compatible with SIP settings
- **User Approval**: Interactive approval required in System Preferences

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

### System Extension Management

```bash
# Install and register the System Extension
sudo usbipd install-system-extension

# Run comprehensive installation diagnostics
usbipd diagnose

# Run verbose diagnostics with detailed information
usbipd diagnose --verbose

# Check System Extension status and health
usbipd status --verbose
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

# Build the project (includes System Extension bundle creation)
swift build

# Install System Extension for development
sudo usbipd install-system-extension

# Run diagnostics to verify installation
usbipd diagnose

# Check detailed status including bundle information
usbipd status --verbose
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

1. **Create and Edit Changelog**:
   ```bash
   # Manually edit CHANGELOG.md to document changes for the release
   # Add entries under the [Unreleased] section
   # Follow Keep a Changelog format
   ```

2. **Commit Changelog**:
   ```bash
   # Commit the changelog updates
   git add CHANGELOG.md
   git commit -m "docs: update changelog for v1.2.3 release"
   ```

3. **Prepare Release Locally**:
   ```bash
   # Prepare specific version (will prompt to review auto-generated changelog)
   ./Scripts/prepare-release.sh --version v1.2.3
   
   # The script will:
   # - Update CHANGELOG.md with version entry
   # - Pause for you to manually edit the changelog
   # - Run validation, tests, and create the Git tag
   ```
   
   Available options:
   - `--version VERSION`: Specific version (e.g., v1.2.3 or 1.2.3)
   - `--dry-run`: Preview actions without making changes
   - `--skip-tests`: Skip test execution (not recommended)
   - `--skip-lint`: Skip code quality checks (not recommended)
   - `--force`: Override safety checks and skip manual changelog review

4. **Push Release Tag**:
   ```bash
   # Push the created tag to trigger automated workflows
   git push origin v1.2.3
   ```

5. **Automated Pipeline**: Once a version tag is pushed, GitHub Actions automatically:
   - Validates the release candidate
   - Builds production artifacts with code signing
   - Runs comprehensive test validation
   - **Updates Homebrew formula automatically**
   - Creates GitHub release with artifacts and checksums
   - Pushes formula changes back to the repository

6. **Emergency Releases**: For critical fixes, use `--force` to skip manual changelog review and validation.

#### Homebrew Formula Management

**Fully Automated Formula Updates**: The Homebrew formula is now integrated directly into this repository and is updated completely automatically during the release workflow.

**Complete Formula Update Process**:

The release workflow automatically handles the entire formula update process:
- Updates `Formula/usbipd-mac.rb` with new version and checksum
- Validates the updated formula syntax and structure
- Commits and pushes changes back to the main branch
- Makes the formula available through the `beriberikix/usbipd-mac` tap

**No manual intervention required** - users can install and update through Homebrew immediately after a release is published.

**Formula Testing and Validation**:
```bash
# Test formula syntax locally
./Scripts/validate-formula.sh

# Test installation from tap
brew uninstall usbipd-mac || true
brew untap beriberikix/usbipd-mac || true
brew tap beriberikix/usbipd-mac
brew install usbipd-mac
```

**Manual Formula Operations** (for testing/troubleshooting):
```bash
# Preview formula update
./Scripts/update-formula.sh --version v1.2.3 --dry-run

# Rollback formula to previous version
./Scripts/update-formula.sh --rollback
```

#### Versioning Strategy

- **Semantic Versioning**: Follow semver (MAJOR.MINOR.PATCH) for all releases
- **Release Schedule**: Monthly minor releases with patch releases as needed
- **Pre-releases**: Use `-alpha`, `-beta`, `-rc` suffixes for testing releases
- **Changelog**: Automatically generated from conventional commits

#### Required Setup

For release automation to work properly:

1. **Code Signing**: Configure Apple Developer certificates in GitHub repository secrets
2. **Permissions**: Ensure maintainer access to repository settings and secrets
3. **Environment**: Validate local environment with release preparation script

Validation commands:
```bash
# Check release preparation environment
./Scripts/prepare-release.sh --help

# Validate formula update tools
./Scripts/update-formula.sh --help

# Validate formula syntax
./Scripts/validate-formula.sh --help
```

See [Release Automation Documentation](Documentation/Release-Automation.md) for complete setup instructions and troubleshooting.

### For Contributors

Release automation is handled by maintainers. Contributors should:
- Follow conventional commit format for automatic changelog generation
- Ensure all PRs pass CI validation before merge
- Report issues with release automation to repository maintainers

## License

[MIT License](LICENSE)