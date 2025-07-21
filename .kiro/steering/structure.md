# Project Structure

## Directory Organization

```
usbipd-mac/
├── Sources/                  # Source code
│   ├── USBIPDCore/           # Core functionality
│   │   ├── Protocol/         # USB/IP protocol implementation
│   │   ├── Device/           # USB device management
│   │   └── Network/          # Network communication
│   ├── SystemExtension/      # System Extension for device access
│   ├── USBIPDCLI/            # Command-line interface
│   ├── QEMUTestServer/       # Lightweight QEMU test server
│   └── Common/               # Shared utilities and models
├── Tests/                    # Test suite
│   ├── USBIPDCoreTests/      # Core functionality tests
│   ├── USBIPDCLITests/       # CLI tests
│   └── IntegrationTests/     # End-to-end tests with QEMU
├── Resources/                # Resource files
├── Documentation/            # Additional documentation
├── Scripts/                  # Build and utility scripts
│   └── run-qemu-tests.sh     # QEMU test validation script
└── .github/                  # GitHub configuration
    └── workflows/            # GitHub Actions CI workflows
```

## Architecture Patterns

### Core Architecture
- Follow a modular design with clear separation of concerns
- Use protocol-oriented programming for interfaces
- Implement dependency injection for testability
- Follow patterns established in usbipd-win where appropriate

### Component Responsibilities
- **Protocol Layer**: Handles USB/IP protocol encoding/decoding according to specification
- **Device Layer**: Manages USB device discovery, claiming, and interaction via IOKit
- **System Extension**: Provides privileged access to USB devices
- **Network Layer**: Handles network connections and data transfer
- **CLI**: Provides command-line interface to the core functionality
- **QEMU Test Server**: Implements minimal functionality for validation testing

## File Naming Conventions
- Swift files: PascalCase matching the type name (e.g., `DeviceManager.swift`)
- Extensions: Named with the extended type and functionality (e.g., `Device+Serialization.swift`)
- Test files: Match source files with "Tests" suffix (e.g., `DeviceManagerTests.swift`)
- Shell scripts: Use kebab-case (e.g., `run-qemu-tests.sh`)

## Import Organization
- Group imports by standard library, third-party, and internal modules
- Place Foundation and system imports first, followed by third-party libraries, then internal modules

## CI/CD Structure
- GitHub Actions for continuous integration
- SwiftLint for code style validation
- Build validation against latest Swift and macOS versions
- QEMU test server validation as part of the test suite