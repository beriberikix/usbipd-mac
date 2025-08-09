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

## System Extension Bundle Support

This project includes full System Extension bundle support for secure USB device access on macOS. System Extensions provide a modern, secure way to access USB devices without requiring kernel extensions.

### Requirements

- **macOS 11.0+**: System Extensions are only supported on macOS Big Sur and later
- **Code Signing**: System Extension bundles require valid Developer ID or development certificates
- **User Approval**: First-time installation requires user approval in System Preferences

### System Extension Bundle Creation

The build system automatically creates System Extension bundles during compilation:

```bash
# Build creates SystemExtension.systemextension bundle automatically
swift build

# The bundle is created at:
# .build/[arch]-apple-macosx/debug/SystemExtension.systemextension/
```

### Bundle Structure

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

### Installation and Activation

#### Development Mode

For development and testing, enable System Extension development mode:

```bash
# Enable developer mode (requires reboot)
systemextensionsctl developer on

# Reset System Extensions if needed
systemextensionsctl reset
```

#### Production Installation

System Extensions are installed automatically when the USB/IP daemon starts:

```bash
# Install and activate System Extension
sudo usbipd daemon --install-extension

# Check System Extension status
usbipd status
```

### System Extension Troubleshooting

#### Common Issues

**"System Extension Blocked"**
- Open System Preferences > Privacy & Security > General
- Click "Allow" next to the blocked System Extension notification
- Restart the USB/IP daemon

**"Extension Not Found"**
```bash
# Verify bundle exists
ls -la .build/arm64-apple-macosx/debug/SystemExtension.systemextension

# Check bundle signature
codesign -v .build/arm64-apple-macosx/debug/SystemExtension.systemextension

# View System Extension status
systemextensionsctl list
```

**"Permission Denied"**
```bash
# Check System Extension is properly signed
spctl -a -t install .build/arm64-apple-macosx/debug/SystemExtension.systemextension

# Verify entitlements
codesign -d --entitlements - .build/arm64-apple-macosx/debug/SystemExtension.systemextension
```

#### Development Troubleshooting

**Build Issues:**
```bash
# Clean build if bundle creation fails
swift package clean
swift build

# Check plugin execution
swift build --verbose 2>&1 | grep "SystemExtensionBundleBuilder"
```

**Runtime Issues:**
```bash
# View System Extension logs
log show --predicate 'subsystem == "com.usbipd.mac.system-extension"' --last 1h

# Check USB/IP daemon logs
log show --predicate 'subsystem == "com.usbipd.mac"' --last 1h
```

#### Advanced Troubleshooting

For complex System Extension issues:

1. **Reset System Extensions**: `systemextensionsctl reset` (requires reboot)
2. **Check System Integrity**: `sudo spctl --assess --type install [bundle-path]`
3. **Verify Code Signing**: `codesign -dv --verbose=4 [bundle-path]`
4. **System Extension Logs**: Use Console.app and filter for "systemextensionsd"

See [System Extension Setup Guide](Sources/SystemExtension/SYSTEM_EXTENSION_SETUP.md) for detailed development setup instructions.

## Project Status

This project is currently in early development. The core server functionality is being implemented as an MVP.

## Building the Project

### Prerequisites

- **Xcode 13+**: Required for System Extensions support and Swift Package Manager
- **macOS 11.0+ SDK**: System Extensions require macOS Big Sur SDK or later  
- **Code Signing**: Optional for development, required for distribution
  - Development: Use Xcode automatic signing
  - Production: Valid Developer ID certificate

### Build Commands

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

### Build Artifacts

After building, the following artifacts are created:

```
.build/[arch]-apple-macosx/debug/
├── usbipd                                      # Main CLI executable
├── SystemExtension                             # System Extension executable
├── SystemExtension.systemextension/            # Complete System Extension bundle
│   ├── Contents/
│   │   ├── Info.plist
│   │   ├── MacOS/SystemExtension
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

## Running Tests

```bash
# Run all tests using Swift Package Manager
swift test

# Run tests using Xcode
xcodebuild -scheme usbipd-mac test

# Run specific test suites
swift test --filter USBIPDCoreTests          # Core functionality tests
swift test --filter USBIPDCLITests           # CLI interface tests
swift test --filter SystemExtensionTests     # System Extension tests
swift test --filter IntegrationTests         # Integration tests

# Run QEMU test server validation
./Scripts/run-qemu-tests.sh

# Test System Extension functionality (requires development mode)
swift test --filter IntegrationTests --verbose
```

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

## Continuous Integration

This project uses GitHub Actions for continuous integration to ensure code quality and prevent regressions. The CI pipeline automatically runs on every pull request and push to the main branch, providing fast feedback to developers.

### CI Pipeline Overview

The CI pipeline consists of four parallel jobs that validate different aspects of the codebase:

#### 1. Code Quality (SwiftLint)
- **Purpose**: Validates Swift code style and consistency
- **Tool**: SwiftLint with project-specific configuration (`.swiftlint.yml`)
- **Execution**: Runs in strict mode where warnings are treated as errors
- **Caching**: SwiftLint installation is cached for faster execution

#### 2. Build Validation
- **Purpose**: Ensures the project compiles successfully
- **Tool**: Swift Package Manager with latest Swift version
- **Environment**: Latest macOS runner with verbose build output
- **Caching**: Swift packages and build artifacts are cached

#### 3. Unit Tests
- **Purpose**: Validates functionality through automated unit tests
- **Coverage**: USBIPDCoreTests and USBIPDCLITests suites
- **Execution**: Parallel test execution with verbose output
- **Environment**: Latest Swift and macOS versions

#### 4. Integration Tests (QEMU)
- **Purpose**: End-to-end validation with QEMU test server
- **Components**: QEMU test server build and validation script
- **Coverage**: Network communication and protocol flow testing
- **Dependencies**: Builds QEMUTestServer product and runs validation script

### Running Checks Locally

Before submitting a pull request, you can run the same checks locally to catch issues early:

#### Code Quality Check
```bash
# Install SwiftLint (if not already installed)
brew install swiftlint

# Run SwiftLint with the same strict settings as CI
swiftlint lint --strict

# Auto-fix some violations (optional)
swiftlint --fix
```

#### Build Validation
```bash
# Clean build to match CI environment
swift package clean

# Resolve dependencies
swift package resolve

# Build project with verbose output
swift build --verbose
```

#### Unit Tests
```bash
# Run all unit tests with parallel execution
swift test --parallel --verbose

# Run specific test suite
swift test --filter USBIPDCoreTests
swift test --filter USBIPDCLITests
```

#### Integration Tests
```bash
# Build QEMU test server
swift build --product QEMUTestServer

# Run QEMU validation script
./Scripts/run-qemu-tests.sh

# Run integration tests specifically
swift test --filter IntegrationTests --verbose
```

#### Complete Local Validation
```bash
# Run all checks in sequence (mimics CI pipeline)
echo "Running SwiftLint..."
swiftlint lint --strict

echo "Building project..."
swift build --verbose

echo "Running unit tests..."
swift test --parallel --verbose

echo "Running integration tests..."
./Scripts/run-qemu-tests.sh
swift test --filter IntegrationTests --verbose

echo "All checks completed successfully!"
```

### Performance Optimization

The CI pipeline is optimized for fast feedback:

- **Parallel Execution**: All four jobs run simultaneously
- **Dependency Caching**: Swift packages and SwiftLint are cached between runs
- **Incremental Builds**: Build artifacts are cached when possible
- **Target Execution Time**: Complete pipeline typically runs under 10 minutes

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
```

This ensures that even if technical checks could be bypassed, maintainer approval acts as a safeguard to maintain code quality and project stability.

**Maintainer Approval Process:**

When CI checks fail or need to be bypassed (satisfying requirement 6.4):

1. **Normal Process**: Fix the failing checks and push new commits
2. **Emergency Bypass**: 
   - Requires explicit approval from repository maintainers
   - Maintainer must review the specific reason for bypass
   - Approval must be documented in PR comments
   - Follow-up issue should be created to address the underlying problem

**Configuration Details:**
- Administrators cannot bypass protection rules without approval
- All status checks must pass before merging
- At least 1 maintainer approval is required for all PRs
- Stale reviews are dismissed when new commits are pushed

See [Branch Protection Configuration](.github/branch-protection-config.md) for detailed setup instructions.

### Troubleshooting CI Issues

If CI checks fail, here are common solutions and next steps:

#### Quick Diagnosis Steps

1. **Identify the failing job**: Check which specific job failed (lint, build, test, integration-test)
2. **Review error summary**: Each job provides a summary with common causes
3. **Run locally first**: Always reproduce the issue locally before investigating CI-specific problems
4. **Check recent changes**: Consider if recent updates might be the cause

#### Common Issues and Solutions

**SwiftLint Failures:**
```bash
# Check violations locally
swiftlint lint --strict

# Auto-fix violations where possible
swiftlint --fix

# Verify configuration
python -c "import yaml; yaml.safe_load(open('.swiftlint.yml'))"
```

**Build Failures:**
```bash
# Clean build to match CI environment
swift package clean
swift package resolve
swift build --verbose

# Check for dependency conflicts
swift package show-dependencies
```

**Test Failures:**
```bash
# Run tests with detailed output
swift test --verbose --parallel

# Run specific test suite
swift test --filter USBIPDCoreTests
swift test --filter USBIPDCLITests
```

**Integration Test Failures:**
```bash
# Build and test QEMU server
swift build --product QEMUTestServer
./Scripts/run-qemu-tests.sh

# Run integration tests specifically
swift test --filter IntegrationTests --verbose
```

#### Updating Swift and macOS Versions

When new Swift or macOS versions become available:

**Swift Version Updates:**
1. Update `Package.swift` tools version: `// swift-tools-version:5.9`
2. Test locally: `swift build && swift test`
3. Update CI if using specific version (workflow uses `latest` by default)
4. Handle deprecated APIs and breaking changes

**macOS Version Updates:**
1. CI automatically uses `macos-latest` (currently macOS 13+)
2. Update minimum deployment target if needed: `.macOS(.v13)`
3. Add availability checks for new APIs:
   ```swift
   if #available(macOS 14.0, *) {
       // Use new API
   } else {
       // Fallback implementation
   }
   ```

#### Performance Issues

If CI execution exceeds 10 minutes:
- Check dependency caching effectiveness
- Profile slow tests: `swift test --verbose 2>&1 | grep "Test Case.*passed"`
- Optimize build configuration for performance testing
- Consider parallel execution improvements

#### For Comprehensive Troubleshooting

See the detailed [CI Troubleshooting Guide](.github/CI_TROUBLESHOOTING.md) which covers:
- Detailed diagnosis procedures for each job type
- Step-by-step solutions for common issues
- Swift and macOS version update procedures
- Cache optimization and debugging
- Branch protection troubleshooting
- Emergency procedures for critical issues

#### Getting Help

If these solutions don't resolve your issue:
1. Check the [comprehensive troubleshooting guide](.github/CI_TROUBLESHOOTING.md)
2. Review CI job logs for detailed error messages
3. Reproduce the issue locally using the same commands
4. Check [GitHub Actions status](https://www.githubstatus.com/) for platform issues
5. Consult project maintainers for project-specific guidance

## License

[MIT License](LICENSE)