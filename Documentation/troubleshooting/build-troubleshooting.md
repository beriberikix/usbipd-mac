# Build and Development Troubleshooting

This guide provides solutions for common build and development issues encountered when working with usbipd-mac.

## Build Setup and Prerequisites

### System Requirements

- **Xcode 13+**: Required for System Extensions support and Swift Package Manager
- **macOS 11.0+ SDK**: System Extensions require macOS Big Sur SDK or later  
- **Code Signing**: Optional for development, required for distribution
  - Development: Use Xcode automatic signing
  - Production: Valid Developer ID certificate

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

## Common Build Issues

### Build Failures

```bash
# Clean build to match CI environment
swift package clean
swift package resolve
swift build --verbose

# Check for dependency conflicts
swift package show-dependencies
```

### Bundle Creation Issues

**Build Issues:**
```bash
# Clean build if bundle creation fails
swift package clean
swift build

# Check plugin execution
swift build --verbose 2>&1 | grep "SystemExtensionBundleBuilder"
```

### Dependencies and Package Resolution

```bash
# Resolve dependencies explicitly
swift package resolve

# Update package dependencies
swift package update

# Reset package cache if needed
swift package reset
```

## Code Quality Issues

### SwiftLint Failures

```bash
# Check violations locally
swiftlint lint --strict

# Auto-fix violations where possible
swiftlint --fix

# Verify configuration
python -c "import yaml; yaml.safe_load(open('.swiftlint.yml'))"
```

## Testing Issues

### Test Failures

```bash
# Run tests with detailed output
swift test --verbose --parallel

# Run specific test suite
swift test --filter USBIPDCoreTests
swift test --filter USBIPDCLITests
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

### Integration Test Failures

```bash
# Build and test QEMU server
swift build --product QEMUTestServer
./Scripts/qemu-test-validation.sh

# Run integration tests specifically
swift test --filter IntegrationTests --verbose
```

## CI and Development Validation

### Running Checks Locally

Before submitting a pull request, you can run the same checks locally to catch issues early:

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
./Scripts/qemu-test-validation.sh
swift test --filter IntegrationTests --verbose

echo "All checks completed successfully!"
```

## Version Compatibility Issues

### Swift Version Updates

When new Swift versions become available:

1. Update `Package.swift` tools version: `// swift-tools-version:5.9`
2. Test locally: `swift build && swift test`
3. Update CI if using specific version (workflow uses `latest` by default)
4. Handle deprecated APIs and breaking changes

### macOS Version Updates

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

## Performance Issues

If build execution is slow:
- Check dependency caching effectiveness
- Profile slow tests: `swift test --verbose 2>&1 | grep "Test Case.*passed"`
- Optimize build configuration for performance testing
- Consider parallel execution improvements

## Getting Help

If these solutions don't resolve your issue:

1. Check the [System Extension troubleshooting guide](system-extension-troubleshooting.md)
2. Review build logs for detailed error messages
3. Reproduce the issue with verbose output: `swift build --verbose`
4. Check [GitHub Actions status](https://www.githubstatus.com/) for platform issues
5. Consult project maintainers for project-specific guidance

## See Also

- [System Extension Troubleshooting](system-extension-troubleshooting.md)
- [CI/CD Documentation](../development/ci-cd.md)
- [Architecture Documentation](../development/architecture.md)