# Technical Stack

## Development Environment
- macOS (primary platform)
- Xcode (recommended IDE)
- Swift (primary programming language)
- System Extensions for device access

## Frameworks & Libraries
- Swift Foundation
- IOKit for USB device interaction
- Network.framework for IP networking
- SystemExtensions framework for device claiming
- QEMU (for test server implementation)

## Build System
- Swift Package Manager (SPM)
- Xcode build system
- GitHub Actions for CI

## Common Commands

### Building the Project
```bash
# Build using Swift Package Manager
swift build

# Build using Xcode
xcodebuild -scheme usbipd-mac build
```

### Running Tests
```bash
# Run tests using Swift Package Manager
swift test

# Run tests using Xcode
xcodebuild -scheme usbipd-mac test

# Run QEMU test server validation
./Scripts/run-qemu-tests.sh

### Installing Dependencies
```bash
# Update dependencies
swift package update
```

## Code Style
- Follow Swift API Design Guidelines
- Use SwiftLint for code style enforcement (validated in CI)
- Prefer Swift's native error handling over Objective-C patterns
- Use strong typing and avoid force unwrapping

## Documentation
- Use Swift's documentation comments (///) for public APIs
- Document complex algorithms and non-obvious behavior
- Keep README updated with usage instructions
- Include references to USB/IP protocol specification where relevant

## Git Workflow
- Implement new features in dedicated branches
- Group related changes into logical commits
- Ensure GitHub Actions pass before merging
- Follow conventional commit message format
- Create pull requests for code review before merging to main