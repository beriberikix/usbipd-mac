# Project Structure

## Directory Organization

```
usbipd-mac/
├── Sources/                    # Source code organized by target
│   ├── Common/                # Shared utilities across targets
│   │   ├── Errors.swift       # Common error definitions
│   │   └── Logger.swift       # Unified logging system
│   ├── USBIPDCore/            # Core library implementation
│   │   ├── Device/            # USB device discovery and management
│   │   ├── Network/           # TCP server and connection handling
│   │   ├── Protocol/          # USB/IP protocol implementation
│   │   ├── ServerConfig.swift # Configuration management
│   │   ├── ServerCoordinator.swift # Main coordination logic
│   │   └── USBIPServer.swift  # Primary server interface
│   ├── USBIPDCLI/             # Command-line interface
│   │   ├── CommandLineParser.swift # Argument parsing
│   │   ├── Commands.swift     # CLI command implementations
│   │   ├── OutputFormatter.swift # Output formatting utilities
│   │   └── main.swift         # CLI entry point
│   ├── SystemExtension/       # macOS System Extension
│   │   └── SystemExtension.swift # System Extension implementation
│   └── QEMUTestServer/        # Test validation server
│       └── main.swift         # QEMU test server entry point
├── Tests/                     # Test suites organized by target
│   ├── USBIPDCoreTests/       # Core library unit tests
│   │   └── Mocks/            # Test doubles and fixtures
│   ├── USBIPDCLITests/        # CLI interface tests
│   └── IntegrationTests/      # End-to-end integration tests
├── Scripts/                   # Build and test automation
│   └── examples/             # Example usage scripts
├── Documentation/             # Project documentation
└── Package.swift             # Swift Package Manager manifest
```

## Naming Conventions

### Files
- **Swift Source Files**: `PascalCase` for classes/structs/protocols (e.g., `DeviceDiscovery.swift`)
- **Utilities/Helpers**: `PascalCase` with descriptive suffixes (e.g., `EncodingUtilities.swift`)
- **Entry Points**: `main.swift` for executable targets
- **Tests**: `[Module/Feature]Tests.swift` pattern (e.g., `ServerCoordinatorTests.swift`)
- **Mock Objects**: `Mock[InterfaceName].swift` pattern (e.g., `MockIOKitInterface.swift`)

### Code
- **Classes/Types**: `PascalCase` (e.g., `DeviceMonitor`, `TCPServer`, `USBIPProtocol`)
- **Functions/Methods**: `camelCase` (e.g., `discoverDevices()`, `startServer()`, `processRequest()`)
- **Constants**: `camelCase` for instance constants, `UPPER_SNAKE_CASE` for static/global (e.g., `DEFAULT_PORT`)
- **Variables**: `camelCase` (e.g., `deviceList`, `connectionCount`, `serverConfig`)

## Import Patterns

### Import Order
1. Foundation and system frameworks (Foundation, IOKit, Network)
2. External dependencies (currently none - pure Swift/system implementation)
3. Internal modules (Common, USBIPDCore for CLI)
4. Relative imports within same target (rare - prefer explicit module imports)

### Module/Package Organization
```swift
// Standard pattern for USBIPDCore files
import Foundation
import IOKit
import Network

// Standard pattern for CLI files
import Foundation
import USBIPDCore
import Common

// Standard pattern for tests
import XCTest
@testable import USBIPDCore
@testable import Common
```

## Code Structure Patterns

### Module/Class Organization
```swift
// Standard Swift file organization:
1. Import statements
2. Module-level constants and type aliases
3. Protocol definitions
4. Primary implementation classes/structs
5. Extension blocks for protocol conformances
6. Private helper types and functions
```

### Function/Method Organization
```swift
// Method organization principles:
- Input validation and preconditions first
- Core business logic in the middle
- Error handling integrated throughout (Swift Result/throws pattern)
- Clear return points with proper cleanup
- Logging at appropriate levels (debug, info, error)
```

### File Organization Principles
```swift
// File structure guidelines:
- One primary public type per file
- Related helper types in same file if tightly coupled
- Public API at the top of class/struct definitions
- Private implementation details at the bottom
- Protocol conformances in separate extensions
```

## Code Organization Principles

1. **Single Responsibility**: Each Swift file contains one primary abstraction (class, protocol, or related group)
2. **Modularity**: Clear target boundaries with well-defined public APIs and internal implementation details
3. **Testability**: Code structured to support dependency injection and comprehensive test coverage
4. **Consistency**: Follow established patterns from Swift standard library and Apple frameworks

## Module Boundaries

### Core Architecture Boundaries
- **Common → All Targets**: Shared utilities flow outward to all other modules
- **USBIPDCore → CLI/Extensions**: Core library provides APIs consumed by interface layers
- **SystemExtension ← USBIPDCore**: System Extension depends on core library for implementation
- **QEMUTestServer ← Common**: Test server uses only shared utilities, isolated from core business logic

### Dependency Direction Rules
- **Upward Dependencies**: Lower-level modules (Common) never depend on higher-level modules (CLI)
- **Cross-Module APIs**: Public interfaces clearly defined in module headers
- **Internal Implementation**: Private types and functions not exposed across module boundaries
- **Test Dependencies**: Test targets can access internal APIs via @testable imports

### Platform-specific vs Cross-platform
- **IOKit Integration**: Platform-specific code isolated to Device/ subdirectory
- **Network Layer**: Cross-platform Swift Network framework usage
- **Protocol Implementation**: Platform-agnostic USB/IP protocol handling
- **System Integration**: macOS-specific features (System Extensions) in dedicated targets

## Code Size Guidelines

### File Size Guidelines
- **Primary Files**: Aim for 200-400 lines per Swift source file
- **Complex Classes**: Break into extensions or separate related types when exceeding 500 lines
- **Protocol Files**: Group related protocols, keep individual protocols focused and concise
- **Test Files**: One test class per source class, unlimited size for comprehensive coverage

### Function/Method Size Guidelines
- **Method Length**: Target 20-50 lines per method, maximum 100 lines for complex operations
- **Function Complexity**: Break down complex logic into private helper methods
- **Error Handling**: Use Swift's Result type and throwing functions for clean error propagation
- **Async Operations**: Leverage Swift Concurrency (async/await) for asynchronous operations

### Nesting Guidelines
- **Maximum Nesting**: 4 levels of nesting (if/guard/for/while combinations)
- **Early Returns**: Prefer guard statements and early returns over deeply nested conditional logic
- **Switch Statements**: Use exhaustive switch statements with clear case handling
- **Closure Nesting**: Limit nested closures, prefer named functions for complex operations

## Documentation Standards

### Swift Documentation Format
- **Public APIs**: Comprehensive documentation using Swift DocC format (`///`)
- **Complex Logic**: Inline comments (`//`) explaining algorithm choices and business logic
- **Protocol Conformances**: Document protocol implementation requirements and constraints
- **Error Handling**: Document all possible errors thrown by functions

### Module Documentation
- **README Files**: High-level module purpose and integration instructions
- **Architecture Documentation**: Located in Documentation/ directory
- **Protocol Reference**: Detailed USB/IP protocol implementation documentation
- **Troubleshooting Guides**: Comprehensive guides for common development and deployment issues