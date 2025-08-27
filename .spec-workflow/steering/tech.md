# Technology Stack

## Project Type
macOS native system utility and library package implementing network protocol server functionality. Built as a Swift Package Manager multi-target project with both executable and library products supporting macOS 11+.

## Core Technologies

### Primary Language(s)
- **Language**: Swift 5.5+
- **Runtime/Compiler**: Swift compiler with macOS 11+ deployment target
- **Language-specific tools**: Swift Package Manager (SPM) for dependency management and build orchestration

### Key Dependencies/Libraries
- **IOKit Framework**: Core framework for USB device discovery, enumeration, and hardware interaction
- **Network Framework**: TCP server implementation and client connection management
- **Foundation**: Core Swift libraries for data types, networking, and system integration
- **XCTest**: Testing framework for unit and integration test suites

### Application Architecture
**Multi-target modular architecture** with clear separation of concerns:
- **USBIPDCore**: Core library containing protocol implementation, device management, and network layer
- **USBIPDCLI**: Command-line executable providing user interface and daemon functionality  
- **SystemExtension**: macOS System Extension for privileged device access and claiming
- **QEMUTestServer**: Validation server for integration testing and protocol compliance
- **Common**: Shared utilities for logging, error handling, and cross-module functionality

The architecture follows a **layered service pattern** with dependency injection and protocol-oriented design.

### Data Storage
- **Primary storage**: In-memory device state management with file system configuration persistence
- **Caching**: Memory-based device enumeration cache with IOKit notification-driven updates
- **Data formats**: USB/IP protocol binary messages, JSON configuration files, Swift Codable for serialization

### External Integrations
- **APIs**: IOKit USB enumeration APIs, macOS System Extension APIs, Network framework APIs
- **Protocols**: USB/IP protocol specification (TCP-based), USB protocol standards
- **Authentication**: macOS privilege escalation and System Extension authorization

## Development Environment

### Build & Development Tools
- **Build System**: Swift Package Manager (swift build, swift test, swift run)
- **Package Management**: SPM with native dependency resolution
- **Development workflow**: Incremental compilation with swift build, live testing with swift test --parallel
- **Secondary Build**: Xcode project generation support (xcodebuild)

### Code Quality Tools
- **Static Analysis**: SwiftLint with comprehensive rule set and strict enforcement
- **Formatting**: SwiftLint auto-fix capabilities for consistent code style
- **Testing Framework**: XCTest with parallel execution support and verbose output
- **Documentation**: Swift DocC compatible documentation generation

### Version Control & Collaboration
- **VCS**: Git with GitHub integration
- **Branching Strategy**: GitHub Flow with feature branches and main branch protection
- **Code Review Process**: Pull request reviews with required status checks and maintainer approval
- **CI/CD**: GitHub Actions with parallel job execution and comprehensive validation

#### Required Git Workflow for Spec Implementation
All specification implementation tasks must follow this mandatory workflow:

1. **Feature Branch Creation**: 
   ```bash
   git checkout -b feature/[spec-name]-[task-description]
   git push -u origin feature/[spec-name]-[task-description]
   ```

2. **Incremental Development**:
   - Commit changes at logical completion points during implementation
   - Push commits regularly to track progress and enable collaboration
   - Use descriptive commit messages following conventional commit format

3. **Continuous Integration**:
   - Run local validation before pushing: `swiftlint lint --strict && swift build --verbose && ./Scripts/run-ci-tests.sh`
   - Monitor GitHub Actions CI status for all pushed commits
   - Address any CI failures immediately

4. **Pull Request Workflow** (Final Task):
   - Create pull request with comprehensive description of changes
   - Link to related specification documents and issues
   - Ensure all CI checks pass (SwiftLint, build validation, test suite)
   - Request code review from maintainers
   - Address review feedback before merge approval

This workflow ensures code quality, enables collaborative review, and maintains project stability through automated validation.

## Deployment & Distribution

### Target Platform(s)
- **Primary**: macOS 11.0+ (Big Sur and later)
- **Architecture**: Universal binaries supporting Intel and Apple Silicon (arm64/x86_64)
- **Distribution**: Open source project with Swift Package Manager integration
- **Installation**: Command-line build and install, future homebrew formula support

### Installation Requirements
- **Prerequisites**: Xcode Command Line Tools or Xcode 13+
- **System Requirements**: macOS 11+, Administrator privileges for System Extension
- **Dependencies**: No external runtime dependencies beyond system frameworks

### Update Mechanism
- **Development**: Git pull and rebuild workflow
- **Future**: Package manager integration for streamlined updates

## Technical Requirements & Constraints

### Performance Requirements
- **Latency**: Sub-50ms USB operation latency over local network
- **Throughput**: Support for high-bandwidth USB devices (USB 3.0+)
- **Memory usage**: Efficient memory management for long-running daemon operation
- **Startup time**: Fast daemon startup and device enumeration

### Compatibility Requirements  
- **Platform Support**: macOS 11.0+ Universal (Intel/Apple Silicon)
- **USB/IP Protocol**: Full compliance with Linux kernel vhci-hcd.ko expectations
- **USB Standards**: Support for USB 1.1/2.0/3.0 device specifications
- **Network Standards**: IPv4/IPv6 TCP socket communication

### Security & Compliance
- **Security Requirements**: 
  - System Extension sandboxing and entitlements
  - Network security with connection validation
  - Privilege separation between daemon and user processes
  - USB device access authorization and claiming
- **Threat Model**: 
  - Network-based attacks through malformed USB/IP packets
  - Local privilege escalation through System Extension vulnerabilities
  - USB device manipulation and unauthorized access

### Scalability & Reliability
- **Expected Load**: Multiple concurrent client connections, dozens of USB devices
- **Availability Requirements**: High uptime for development workflow integration
- **Error Recovery**: Graceful handling of device disconnection, network failures, client crashes

## Technical Decisions & Rationale

### Decision Log
1. **Swift Language Choice**: Native macOS integration, memory safety, modern concurrency support, and excellent IOKit integration
2. **IOKit Direct Integration**: Maximum compatibility and performance with USB device enumeration vs. higher-level abstractions
3. **Swift Package Manager**: Simplifies dependency management, enables modular architecture, and provides excellent tooling integration
4. **System Extension Architecture**: Required for reliable USB device claiming and privileged hardware access on modern macOS
5. **Multi-target Design**: Enables library reuse, supports testing isolation, and provides flexible deployment options

## Known Limitations
[Document any technical debt, limitations, or areas for improvement]

- **System Extension Complexity**: Requires administrator approval and complex deployment process, limiting ease of installation
- **macOS Version Dependency**: IOKit APIs and System Extension requirements limit backward compatibility to macOS 11+
- **USB Device Support**: Some specialized USB device classes may require additional protocol implementation
- **Network Security**: Basic TCP implementation without encryption - future enhancement needed for remote deployment scenarios
- **Performance Optimization**: Initial implementation prioritizes correctness over maximum performance - profiling and optimization needed for high-throughput scenarios