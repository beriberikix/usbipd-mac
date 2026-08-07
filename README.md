> [!IMPORTANT]
> **Which devices work:** those macOS has not bound a driver to. Debug probes
> (J-Link, ST-Link, CMSIS-DAP), boards in DFU or bootloader mode, Android devices in
> ADB mode, and vendor-specific interfaces generally. These need no entitlement and no
> System Extension — a J-Link has been driven end to end from a Linux client with
> probe-rs, and a Pixel answers ADB protocol messages over the wire.
>
> **One caveat even for devices that work:** a client whose protocol keys off USB
> connection or reset events may still not function. `adb` is the known example — it
> waits for the phone's once-per-connection announcement, which macOS already received.
> Request/response devices are unaffected. See
> [Documentation/development/android-adb-validation.md](Documentation/development/android-adb-validation.md).
>
> **Which do not:** anything macOS claims — USB-serial adapters, HID, mass storage,
> audio, cameras. `bind` refuses these with an explanation rather than failing later.
> Releasing them needs the DriverKit USB transport entitlements
> (`com.apple.developer.driverkit`, `com.apple.developer.driverkit.transport.usb`),
> which Apple must approve. **That request was denied on 25 February 2026.** Apple
> redirected it to `com.apple.developer.usb.host-controller-interface`, which enables
> a virtual USB host controller — the capability a USB/IP *client* needs, not the one
> this server needs. See
> [Documentation/development/entitlement-validation.md](Documentation/development/entitlement-validation.md).
>
> Seizing the interface was measured and does **not** work, and neither unmounting nor
> ejecting a device releases it. There is no workaround short of that entitlement.
>
> Note this is *not* the App Sandbox entitlement `com.apple.security.device.usb`, which
> is freely usable and grants nothing here — see
> [Documentation/development/entitlement-validation.md](Documentation/development/entitlement-validation.md).
> Run `./Scripts/validate-usb-entitlements.sh` to check your own hardware.

# usbipd-mac

A macOS implementation of the USB/IP protocol that allows sharing USB devices over IP networks.

## Overview

usbipd-mac is a macOS implementation of the USB/IP protocol that allows sharing USB devices over IP networks. This server implementation enables macOS users to share USB devices with any compatible USB/IP client, with a focus on compatibility with the Linux Kernel virtual HCI driver (vhci-hcd.ko). Docker support on macOS is also a goal.

## Features

- USB device sharing from macOS to other systems over network
- Compatible with the standard Linux `usbip` client — verified with a real client
  performing enumeration, control transfers and bulk transfers
- `bind` refuses devices macOS already owns, naming the owner, instead of failing
  later at transfer time
- No System Extension or entitlement required for the devices it can serve

## Requirements

- **macOS 11.0+**
- **Xcode 13+**: needed to build, and to run the test suite (`swift test` requires
  XCTest, which the Command Line Tools alone do not provide)
- **Code Signing**: optional for development, required for distribution

## Installation

### Homebrew Installation (Recommended)

The easiest way to install usbipd-mac is through Homebrew:

```bash
# Add the usbip tap
brew tap beriberikix/usbipd-mac

# Trust the tap. Homebrew 6 refuses to load formulae from untrusted third-party taps,
# and there is nothing a tap author can do about it — trust is a per-user decision, and
# only official Homebrew taps are trusted automatically.
brew trust beriberikix/usbipd-mac

# Install usbip
brew install usbip
```

Without the trust step: `Refusing to load formula beriberikix/usbipd-mac/usbip from
untrusted tap`. Trusting a single formula rather than the whole tap also works:
`brew trust --formula beriberikix/usbipd-mac/usbip`.

#### Service Management

After installation, you can manage the usbipd daemon using Homebrew services:

```bash
# Start the service (sudo is needed for USB device access)
sudo brew services start usbip

# Stop the service
sudo brew services stop usbip

# Restart the service
sudo brew services restart usbip

# Check service status
brew services info usbip
```

#### System Extension: not required, and not installable this way

There is no System Extension to install. The `install-system-extension` command was
removed, because it could not succeed from a Homebrew prefix:
`OSSystemExtensionRequest` resolves extensions inside the *calling app's* bundle and
requires that bundle to live in `/Applications`, so the staged bundle is never
consulted.

It is also unnecessary. Devices macOS has not bound a driver to are served without any
System Extension, and devices it has bound are not reachable with one either — that
needs a DriverKit entitlement Apple must grant. See
[Documentation/development/driver-free-release.md](Documentation/development/driver-free-release.md).


#### Troubleshooting Homebrew Installation

Common installation issues and solutions:

- **Permission Errors**: run service commands with `sudo`; the daemon needs privileged USB access
- **Service Won't Start**: Verify the binary installed correctly with `which usbipd` and check logs with `brew services list`
- **Version Issues**: Update with `brew upgrade usbip` or reinstall with `brew reinstall usbip`

#### If a device will not bind

`bind` names what owns the device:

```
$ usbipd bind 1-19
Cannot share 1-19: macOS has bound a driver to it (AppleUserHIDDevice).
```

That is a dead end without a DriverKit entitlement — seizing the interface was measured
and does not work, and neither unmounting nor ejecting releases a device.

```
$ usbipd bind 1-20
Cannot share 1-20: another process has it open (AppleUSBHostFrameworkInterfaceClient).
```

That one is fixable: quit the app holding the device and bind again.

To check hardware before buying or debugging, `./Scripts/validate-usb-entitlements.sh`
reports which of your attached devices are claimable and which are owned.

### Manual Installation (Development)

For development or manual installation, see the [Building the Project](#building-the-project) section below.

## Usage

Once installed, you can use usbip to share USB devices over the network:

### Basic Commands

```bash
# List available USB devices
usbipd list

# Share a USB device (device ID from list command)
usbipd bind <busid>

# Check daemon status and shared devices
usbipd status

# Stop sharing a device
usbipd unbind <busid>
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
sudo brew services start usbip

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


## Running Tests

```bash
# Run all tests
swift test

# Run specific test environments (see Documentation for details)
swift test --parallel                 # Run the test suite
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

**External Tap Architecture**: The Homebrew formula is managed in a separate tap repository and is updated automatically via homebrew-releaser GitHub Action during the release workflow.

**Automated Formula Update Process**:

The release workflow uses homebrew-releaser for direct formula updates:
- Homebrew-releaser action automatically updates formula in the external tap repository: [`homebrew-usbipd-mac`](https://github.com/beriberikix/homebrew-usbipd-mac)
- Formula is committed directly to tap repository with proper version and SHA256
- No metadata files or manual intervention required

**Immediate Availability** - users can install and update through Homebrew immediately after a release is published.

**Formula Testing and Validation**:
```bash
# Test installation from tap
brew uninstall usbip || true
brew untap beriberikix/usbipd-mac || true
brew tap beriberikix/usbipd-mac
brew trust beriberikix/usbipd-mac
brew install usbip
```

**Formula Repository**: The formula and automation workflows are maintained in the separate [`homebrew-usbipd-mac`](https://github.com/beriberikix/homebrew-usbipd-mac) repository.

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

# Formula tooling lives in the tap repository, not here:
#   https://github.com/beriberikix/homebrew-usbipd-mac
```

See [Release Automation Documentation](Documentation/Release-Automation.md) for complete setup instructions and troubleshooting.

### For Contributors

Release automation is handled by maintainers. Contributors should:
- Follow conventional commit format for automatic changelog generation
- Ensure all PRs pass CI validation before merge
- Report issues with release automation to repository maintainers

## License

[MIT License](LICENSE)
