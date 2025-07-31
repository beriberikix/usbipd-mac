# Manual Testing Guide

## Overview

The Unit Tests and Integration Tests have been moved to manual execution to reduce CI time and resource usage. These tests can be triggered manually when needed.

## How to Run Manual Tests

### Via GitHub Actions UI

1. Go to the **Actions** tab in the GitHub repository
2. Select the **CI** workflow
3. Click **Run workflow** button
4. Choose which tests to run:
   - ✅ **Run Unit Tests**: Executes comprehensive unit test suite
   - ✅ **Run Integration Tests (QEMU)**: Executes end-to-end integration tests with QEMU

### Automatic CI Checks

The following checks run automatically on every PR:
- ✅ **Code Quality (SwiftLint)**: Validates code style and quality
- ✅ **Build Validation**: Ensures project compiles successfully

## When to Run Manual Tests

### Unit Tests
Run unit tests when:
- Making changes to core functionality
- Before merging significant features
- When debugging test failures
- Before releases

### Integration Tests (QEMU)
Run integration tests when:
- Making changes to network communication
- Modifying USB/IP protocol implementation
- Before major releases
- When validating end-to-end functionality

## Local Testing

You can also run tests locally:

```bash
# Run unit tests
swift test

# Run specific test suites
swift test --filter USBIPDCoreTests
swift test --filter USBIPDCLITests

# Run integration tests
swift test --filter IntegrationTests

# Build and test QEMU server
swift build --product QEMUTestServer
./Scripts/run-qemu-tests.sh
```

## Test Coverage

### Unit Tests
- USBIPDCoreTests: Core functionality validation
- USBIPDCLITests: Command-line interface validation
- Mock-based testing for isolated component validation

### Integration Tests
- QEMU test server functionality
- End-to-end protocol flow validation
- Network communication layer testing
- System integration and compatibility