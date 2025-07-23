# usbipd-mac

A macOS implementation of the USB/IP protocol that allows sharing USB devices over IP networks.

## Overview

usbipd-mac is a macOS implementation of the USB/IP protocol that allows sharing USB devices over IP networks. This server implementation enables macOS users to share USB devices with any compatible USB/IP client, with a focus on compatibility with the Linux Kernel virtual HCI driver (vhci-hcd.ko). Docker support on macOS is also a goal.

## Features

- USB device sharing from macOS to other systems over network
- Full compatibility with the USB/IP protocol specification
- System Extensions integration for reliable device access and claiming
- Lightweight QEMU test server for validation
- Docker enablement for USB device access from containers

## Project Status

This project is currently in early development. The core server functionality is being implemented as an MVP.

## Building the Project

```bash
# Build using Swift Package Manager
swift build

# Build using Xcode
xcodebuild -scheme usbipd-mac build
```

## Running Tests

```bash
# Run tests using Swift Package Manager
swift test

# Run tests using Xcode
xcodebuild -scheme usbipd-mac test

# Run QEMU test server validation
./Scripts/run-qemu-tests.sh
```

## Continuous Integration

This project uses GitHub Actions for continuous integration. The CI pipeline runs on every pull request and push to the main branch, performing:

- **Code Quality Checks**: SwiftLint validation for consistent code style
- **Build Validation**: Ensures the project compiles successfully with Swift Package Manager
- **Unit Tests**: Runs all unit tests to verify functionality
- **Integration Tests**: Validates QEMU test server functionality and end-to-end flows

### Branch Protection

The main branch is protected with required status checks and approval requirements. Pull requests cannot be merged until:

**Required Status Checks:**
- Code Quality (SwiftLint) ✅
- Build Validation ✅  
- Unit Tests ✅
- Integration Tests (QEMU) ✅

**Approval Requirements:**
- At least 1 maintainer review and approval ✅
- Branch must be up to date with main ✅
- Stale reviews dismissed on new commits ✅
- Administrators cannot bypass without approval ✅

**Setup and Validation:**
```bash
# Using the provided setup script
./.github/scripts/setup-branch-protection.sh

# Or validate existing configuration
./.github/scripts/validate-branch-protection.sh
```

This ensures that even if technical checks could be bypassed, maintainer approval acts as a safeguard to maintain code quality and project stability.

See [Branch Protection Configuration](.github/BRANCH_PROTECTION.md) for detailed setup instructions.

## License

[MIT License](LICENSE)