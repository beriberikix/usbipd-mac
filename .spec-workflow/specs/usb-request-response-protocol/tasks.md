# Implementation Plan: USB Request/Response Protocol

## Task Overview

This implementation transforms the current USB/IP server from device enumeration-only to full USB I/O forwarding. The tasks are organized to build incrementally from core infrastructure through protocol message support, IOKit integration, and comprehensive testing. Each task is designed to be atomic, completable within 15-30 minutes, and focuses on specific file modifications with clear deliverables.

The implementation follows the existing Swift architecture patterns, leveraging async/await concurrency, protocol-oriented design, and the modular structure established in the codebase. Tasks prioritize code reuse, extending existing components like RequestProcessor, USBIPProtocol messages, and IOKitDeviceDiscovery rather than creating parallel systems.

Each task includes a git commit to track progress and maintain a clean development history, with the final task creating a PR and ensuring all CI checks pass.

## Tasks

- [x] 0. Setup Development Branch
- [x] 0.1 Create feature branch for USB request/response implementation
  - Command: `git checkout -b feature/usb-request-response-protocol`
  - Purpose: Create dedicated development branch from main for feature work
  - Commit: Initial branch creation for USB request/response protocol implementation
  - _Requirements: Development workflow setup_

- [x] 1. Core USB Request Infrastructure
- [x] 1.1 Create USB request data models in Sources/USBIPDCore/Protocol/USBRequestModels.swift
  - File: Sources/USBIPDCore/Protocol/USBRequestModels.swift
  - Define USBRequestBlock, USBTransferResult, USBTransferType enums
  - Add USB error code mapping utilities and IOKit error translation
  - Purpose: Establish foundational data structures for USB request processing
  - Commit: Add USB request data models and error handling utilities
  - _Leverage: Sources/USBIPDCore/Protocol/USBIPMessages.swift patterns_
  - _Requirements: 1.1, 3.1, 6.1_

- [x] 1.2 Extend RequestProcessor with USB request routing in Sources/USBIPDCore/Protocol/RequestProcessor.swift
  - File: Sources/USBIPDCore/Protocol/RequestProcessor.swift (modify existing)
  - Add handleSubmitRequest and handleUnlinkRequest methods to existing RequestProcessor
  - Integrate USB request validation and error handling patterns
  - Purpose: Enable USB request processing within existing request handling architecture
  - Commit: Extend RequestProcessor with USB SUBMIT/UNLINK request routing
  - _Leverage: existing RequestProcessor structure, error handling patterns_
  - _Requirements: 1.1, 1.4, 5.1_

- [x] 1.3 Create USBRequestHandler protocol and implementation in Sources/USBIPDCore/Protocol/USBRequestHandler.swift
  - File: Sources/USBIPDCore/Protocol/USBRequestHandler.swift
  - Define USBRequestHandler protocol with request processing methods
  - Implement basic request routing and device access validation
  - Purpose: Provide modular USB request handling interface for RequestProcessor integration
  - Commit: Add USBRequestHandler protocol and implementation
  - _Leverage: Sources/USBIPDCore/Device/DeviceClaimManager.swift for validation_
  - _Requirements: 1.1, 1.3, 4.4_

- [x] 2. Enhanced USB/IP Protocol Messages
- [x] 2.1 Add USBIP_CMD_SUBMIT message types to Sources/USBIPDCore/Protocol/USBIPMessages.swift
  - File: Sources/USBIPDCore/Protocol/USBIPMessages.swift (modify existing)
  - Implement USBIPSubmitRequest and USBIPSubmitResponse message structures
  - Add binary encoding/decoding using existing USBIPMessageCodable patterns
  - Purpose: Support USB submit operations in protocol message system
  - Commit: Add USB/IP SUBMIT message types with encoding/decoding support
  - _Leverage: existing USBIPMessageCodable protocols, EndiannessConverter_
  - _Requirements: 5.1, 5.2_

- [x] 2.2 Add USBIP_CMD_UNLINK message types to Sources/USBIPDCore/Protocol/USBIPMessages.swift
  - File: Sources/USBIPDCore/Protocol/USBIPMessages.swift (continue from task 2.1)
  - Implement USBIPUnlinkRequest and USBIPUnlinkResponse message structures
  - Add message validation and error handling for unlink operations
  - Purpose: Enable USB request cancellation through protocol messages
  - Commit: Add USB/IP UNLINK message types with validation
  - _Leverage: existing message patterns, protocol validation utilities_
  - _Requirements: 5.3, 5.4_

- [x] 2.3 Create message processor implementations in Sources/USBIPDCore/Protocol/USBSubmitProcessor.swift
  - File: Sources/USBIPDCore/Protocol/USBSubmitProcessor.swift
  - Implement USBIPSubmitProcessor with request processing and response generation
  - Add URB lifecycle management and concurrent request tracking
  - Purpose: Process SUBMIT requests and coordinate USB transfer execution
  - Commit: Implement USB SUBMIT request processor with URB lifecycle management
  - _Leverage: async/await patterns, existing protocol message handling_
  - _Requirements: 3.1, 3.2, 3.5_

- [x] 2.4 Create unlink processor in Sources/USBIPDCore/Protocol/USBUnlinkProcessor.swift
  - File: Sources/USBIPDCore/Protocol/USBUnlinkProcessor.swift
  - Implement USBIPUnlinkProcessor with URB cancellation capabilities
  - Add pending request tracking and cancellation status reporting
  - Purpose: Handle USB request cancellation through UNLINK operations
  - Commit: Implement USB UNLINK processor with request cancellation
  - _Leverage: concurrent processing patterns, URB tracking system_
  - _Requirements: 3.1, 3.5_

- [x] 3. IOKit USB Device Communication Layer
- [x] 3.1 Create USB device communicator interface in Sources/USBIPDCore/Device/USBDeviceCommunicator.swift
  - File: Sources/USBIPDCore/Device/USBDeviceCommunicator.swift
  - Define USBDeviceCommunicator protocol with transfer type methods
  - Add USB interface lifecycle management (open/close operations)
  - Purpose: Abstract USB device communication layer for protocol processors
  - Commit: Add USB device communication interface and lifecycle management
  - _Leverage: Sources/USBIPDCore/Device/IOKitDeviceDiscovery.swift patterns_
  - _Requirements: 4.1, 4.2_

- [x] 3.2 Implement IOKit USB interface wrapper in Sources/USBIPDCore/Device/IOKitUSBInterface.swift
  - File: Sources/USBIPDCore/Device/IOKitUSBInterface.swift
  - Create IOKitUSBInterface class with IOKit USB family API integration
  - Implement control, bulk, interrupt, and isochronous transfer methods
  - Purpose: Provide low-level USB device communication through IOKit
  - Commit: Implement IOKit USB interface wrapper with all transfer types
  - _Leverage: existing IOKit patterns, device discovery implementations_
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 4.3_

- [x] 3.3 Add USB transfer execution logic to Sources/USBIPDCore/Device/USBDeviceCommunicator.swift
  - File: Sources/USBIPDCore/Device/USBDeviceCommunicator.swift (continue from task 3.1)
  - Implement concrete transfer methods using IOKitUSBInterface
  - Add transfer timeout, error handling, and result processing
  - Purpose: Execute USB transfers and return formatted results
  - Commit: Add USB transfer execution with timeout and error handling
  - _Leverage: IOKitUSBInterface, error handling patterns_
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 4.3_

- [x] 3.4 Integrate device claiming validation in Sources/USBIPDCore/Device/USBDeviceCommunicator.swift
  - File: Sources/USBIPDCore/Device/USBDeviceCommunicator.swift (continue from task 3.3)
  - Add device claim status validation before USB operations
  - Integrate with existing DeviceClaimManager and SystemExtension
  - Purpose: Ensure USB operations only occur on properly claimed devices
  - Commit: Integrate device claiming validation with USB operations
  - _Leverage: Sources/USBIPDCore/Device/DeviceClaimManager.swift_
  - _Requirements: 4.4, 4.5, 6.2_

- [ ] 4. Enhanced Error Handling and Integration
- [ ] 4.1 Create USB error handling utilities in Sources/Common/USBErrorHandling.swift
  - File: Sources/Common/USBErrorHandling.swift
  - Implement IOKit to USB status code mapping functions
  - Add USB error type definitions and protocol error responses
  - Purpose: Provide consistent error handling across USB operations
  - Commit: Add comprehensive USB error handling and IOKit error mapping
  - _Leverage: Sources/Common/ErrorTypes.swift patterns_
  - _Requirements: 6.1, 6.4_

- [ ] 4.2 Add concurrent request processing to Sources/USBIPDCore/Network/ServerCoordinator.swift
  - File: Sources/USBIPDCore/Network/ServerCoordinator.swift (modify existing)
  - Enhance server coordinator to handle increased USB request message volume
  - Add concurrent processing capabilities for multiple USB operations
  - Purpose: Enable efficient handling of concurrent USB requests
  - Commit: Enhance ServerCoordinator with concurrent USB request processing
  - _Leverage: existing ServerCoordinator architecture, async patterns_
  - _Requirements: 1.4, 7.1, 7.4_

- [ ] 4.3 Update server configuration in Sources/USBIPDCore/Configuration/ServerConfig.swift
  - File: Sources/USBIPDCore/Configuration/ServerConfig.swift (modify existing)
  - Add USB operation timeout settings and buffer size limits
  - Configure concurrent request limits and performance parameters
  - Purpose: Provide configurable USB operation parameters
  - Commit: Add USB operation configuration parameters to ServerConfig
  - _Leverage: existing ServerConfig structure and patterns_
  - _Requirements: 7.2, 7.3, 7.5_

- [ ] 5. Comprehensive Testing Infrastructure
- [ ] 5.1 Create USB request model unit tests in Tests/USBIPDCoreTests/Protocol/USBRequestModelsTests.swift
  - File: Tests/USBIPDCoreTests/Protocol/USBRequestModelsTests.swift
  - Write tests for USBRequestBlock, USBTransferResult data structures
  - Test USB error code mapping and IOKit error translation
  - Purpose: Ensure USB data model reliability and error handling accuracy
  - Commit: Add comprehensive unit tests for USB request data models
  - _Leverage: Tests/USBIPDCoreTests/Protocol/ existing test patterns_
  - _Requirements: 1.1, 3.1, 6.1_

- [ ] 5.2 Create USB message encoding tests in Tests/USBIPDCoreTests/Protocol/USBIPMessagesTests.swift
  - File: Tests/USBIPDCoreTests/Protocol/USBIPMessagesTests.swift (modify existing)
  - Add tests for new SUBMIT/UNLINK message encoding and decoding
  - Test message validation and error scenarios for new message types
  - Purpose: Validate protocol message integrity for USB operations
  - Commit: Add USB/IP SUBMIT/UNLINK message encoding/decoding tests
  - _Leverage: existing USBIPMessages test patterns and fixtures_
  - _Requirements: 5.1, 5.2, 5.3, 5.5_

- [ ] 5.3 Create mock IOKit USB interface for testing in Tests/USBIPDCoreTests/Device/MockIOKitUSBInterface.swift
  - File: Tests/USBIPDCoreTests/Device/MockIOKitUSBInterface.swift
  - Implement mock IOKitUSBInterface with controllable responses and errors
  - Add request tracking and validation capabilities for test scenarios
  - Purpose: Enable isolated testing of USB communication layer
  - Commit: Add mock IOKit USB interface for isolated testing
  - _Leverage: Tests/USBIPDCoreTests/Device/ existing mock patterns_
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [ ] 5.4 Create USB device communicator unit tests in Tests/USBIPDCoreTests/Device/USBDeviceCommunicatorTests.swift
  - File: Tests/USBIPDCoreTests/Device/USBDeviceCommunicatorTests.swift
  - Write tests for all USB transfer types using mock IOKit interface
  - Test error handling, timeout scenarios, and device claiming validation
  - Purpose: Ensure USB device communication reliability and error handling
  - Commit: Add comprehensive USB device communicator unit tests
  - _Leverage: MockIOKitUSBInterface, existing device test patterns_
  - _Requirements: 4.1, 4.2, 4.3, 6.3_

- [ ] 5.5 Create USB request processor integration tests in Tests/USBIPDCoreTests/Protocol/USBRequestProcessorTests.swift
  - File: Tests/USBIPDCoreTests/Protocol/USBRequestProcessorTests.swift
  - Write end-to-end tests for SUBMIT/UNLINK request processing
  - Test concurrent request handling and URB lifecycle management
  - Purpose: Validate complete USB request processing flow
  - Commit: Add integration tests for USB request processors
  - _Leverage: mock device communicator, protocol test utilities_
  - _Requirements: 3.1, 3.2, 3.5, 7.1_

- [ ] 6. Integration and System Testing
- [ ] 6.1 Create integration test suite in Tests/IntegrationTests/USBRequestIntegrationTests.swift
  - File: Tests/IntegrationTests/USBRequestIntegrationTests.swift
  - Write tests for complete USB operation flow from client to device
  - Test multiple USB device types and transfer scenarios
  - Purpose: Validate end-to-end USB operation functionality
  - Commit: Add comprehensive USB request integration test suite
  - _Leverage: Tests/IntegrationTests/ existing patterns, test infrastructure_
  - _Requirements: All requirements validation_

- [ ] 6.2 Update CLI integration for USB operations in Sources/USBIPDCLI/Commands/StatusCommand.swift
  - File: Sources/USBIPDCLI/Commands/StatusCommand.swift (modify existing)
  - Add USB operation status reporting to existing status command
  - Display active USB requests, transfer statistics, and error information
  - Purpose: Provide visibility into USB operation status through CLI
  - Commit: Add USB operation status reporting to CLI status command
  - _Leverage: existing StatusCommand structure and device reporting_
  - _Requirements: 7.4, user visibility requirements_

- [ ] 6.3 Add performance validation tests in Tests/PerformanceTests/USBTransferPerformanceTests.swift
  - File: Tests/PerformanceTests/USBTransferPerformanceTests.swift
  - Create performance tests for USB transfer latency and throughput
  - Test concurrent request processing performance and resource usage
  - Purpose: Validate performance requirements and identify bottlenecks
  - Commit: Add USB transfer performance validation tests
  - _Leverage: existing performance test infrastructure_
  - _Requirements: 7.1, 7.2, 7.3_

- [ ] 6.4 Final integration and documentation in Sources/USBIPDCore/README-USB-Implementation.md
  - File: Sources/USBIPDCore/README-USB-Implementation.md
  - Document USB request processing architecture and component interactions
  - Add troubleshooting guide for common USB operation issues
  - Purpose: Provide implementation documentation for maintainers
  - Commit: Add comprehensive USB implementation documentation
  - _Leverage: existing documentation patterns and structure_
  - _Requirements: 6.5, maintainability requirements_

- [ ] 7. CI Validation and Pull Request
- [ ] 7.1 Run comprehensive test suite and fix any failures
  - Commands: `swift test --parallel --verbose`, `./Scripts/run-qemu-tests.sh`
  - Purpose: Ensure all tests pass before creating pull request
  - Action: Fix any test failures or integration issues discovered
  - Commit: Fix test failures and ensure full test suite passes

- [ ] 7.2 Run code quality checks and fix any issues
  - Commands: `swiftlint lint --strict`, validate CI requirements
  - Purpose: Ensure code meets project quality standards
  - Action: Fix any SwiftLint violations or code quality issues
  - Commit: Fix code quality issues and ensure SwiftLint compliance

- [ ] 7.3 Create pull request and ensure CI passes
  - Commands: `git push -u origin feature/usb-request-response-protocol`
  - Create PR with comprehensive description of USB request/response implementation
  - Monitor CI pipeline and fix any failures until all checks pass
  - Purpose: Complete development workflow with successful CI validation
  - Action: Address any CI failures and ensure all automated checks pass