# Requirements Document

## Introduction

The USB Device Communication feature transforms the existing placeholder implementations in the usbipd-mac project into fully functional IOKit-based USB device communication capabilities. This feature enables actual USB device access, transfer operations, and device state management, replacing the current placeholder responses with real USB operations. The implementation will provide the core functionality needed to share USB devices over USB/IP networks by establishing genuine communication channels with physical USB hardware through macOS IOKit frameworks.

This feature builds upon the completed infrastructure (System Extensions, protocols, testing framework) and addresses the most critical gap preventing actual USB device sharing functionality.

## Alignment with Product Vision

This feature directly supports the core product mission of enabling USB device sharing on macOS by:

- **Developer Productivity**: Unlocking real USB device access from containers and VMs instead of placeholder functionality
- **Platform Parity**: Implementing the missing piece for macOS USB/IP compatibility with Linux implementations
- **Performance Objectives**: Enabling the sub-50ms latency target through efficient IOKit integration
- **System Integration**: Leveraging completed System Extension work to provide privileged device access
- **Production Readiness**: Replacing placeholder code with production-quality USB communication

## Requirements

### Requirement 1: IOKit USB Interface Implementation

**User Story:** As a USB/IP server, I want to establish real communication channels with USB devices through IOKit, so that I can execute actual USB transfers instead of returning placeholder responses.

#### Acceptance Criteria

1. WHEN a USB interface needs to be opened THEN the system SHALL use IOKit APIs to establish a genuine device connection interface
2. WHEN IOKit interface creation succeeds THEN the system SHALL track the interface reference for subsequent operations
3. WHEN IOKit interface creation fails THEN the system SHALL throw appropriate USBRequestError with IOKit-specific error details
4. WHEN a USB interface is closed THEN the system SHALL properly release IOKit references and clean up resources
5. IF multiple interfaces are opened concurrently THEN the system SHALL track each interface independently without conflicts

### Requirement 2: USB Transfer Operation Implementation

**User Story:** As a USB/IP protocol handler, I want to execute real USB transfers (control, bulk, interrupt, isochronous), so that clients can perform actual USB operations on shared devices.

#### Acceptance Criteria

1. WHEN a control transfer is requested THEN the system SHALL execute the transfer using IOKit control transfer APIs
2. WHEN a bulk transfer is requested THEN the system SHALL execute the transfer using IOKit bulk transfer APIs  
3. WHEN an interrupt transfer is requested THEN the system SHALL execute the transfer using IOKit interrupt transfer APIs
4. WHEN an isochronous transfer is requested THEN the system SHALL execute the transfer using IOKit isochronous transfer APIs
5. WHEN any transfer completes THEN the system SHALL return actual transfer results including data length, status, and error codes
6. WHEN transfer validation fails THEN the system SHALL throw specific USBRequestError types with detailed error information
7. IF transfer timeout occurs THEN the system SHALL cancel the IOKit operation and return timeout error status

### Requirement 3: Device Claiming and State Management

**User Story:** As a USB/IP server administrator, I want to bind and claim USB devices for exclusive access, so that shared devices can be properly managed and isolated from host system usage.

#### Acceptance Criteria

1. WHEN a device bind operation is requested THEN the system SHALL claim exclusive access to the USB device through System Extension integration
2. WHEN device claiming succeeds THEN the system SHALL mark the device as bound and available for USB/IP sharing
3. WHEN a device unbind operation is requested THEN the system SHALL release exclusive access and return the device to normal host usage
4. WHEN device claiming fails THEN the system SHALL throw DeviceClaimError with specific failure reasons
5. IF a device is already claimed THEN subsequent claim attempts SHALL fail with appropriate error messaging
6. WHEN device state changes THEN the system SHALL update device availability status for client queries

### Requirement 4: USB Request Handler Integration

**User Story:** As a USB/IP client, I want my SUBMIT and UNLINK requests to be processed with actual USB operations, so that I can interact with real hardware instead of receiving placeholder responses.

#### Acceptance Criteria

1. WHEN a USB SUBMIT request is received THEN the system SHALL decode the request and execute the corresponding USB transfer operation
2. WHEN a USB UNLINK request is received THEN the system SHALL cancel the specified pending USB operation
3. WHEN USB operations complete THEN the system SHALL encode proper USB/IP response messages with actual transfer results
4. WHEN USB operations fail THEN the system SHALL return appropriate error responses following USB/IP protocol specifications
5. IF device is not available THEN request processing SHALL fail with device availability errors
6. WHEN concurrent requests occur THEN the system SHALL handle them using URB tracking for proper sequencing

### Requirement 5: CLI Command Implementation

**User Story:** As a developer, I want functional bind/unbind CLI commands, so that I can manage USB device sharing from the command line interface.

#### Acceptance Criteria

1. WHEN "usbipd bind" command is executed THEN the system SHALL claim the specified device for USB/IP sharing
2. WHEN "usbipd unbind" command is executed THEN the system SHALL release the specified device from USB/IP sharing  
3. WHEN bind operation succeeds THEN the CLI SHALL display confirmation with device details
4. WHEN bind operation fails THEN the CLI SHALL display specific error messages and suggested resolutions
5. IF device is already bound THEN bind command SHALL report current binding status
6. WHEN device binding status changes THEN the status command SHALL reflect the current state

### Requirement 6: Error Handling and Diagnostics

**User Story:** As a system administrator, I want comprehensive error reporting and diagnostics for USB operations, so that I can troubleshoot device sharing issues effectively.

#### Acceptance Criteria

1. WHEN IOKit operations fail THEN the system SHALL map IOKit error codes to specific USBRequestError types
2. WHEN USB transfer failures occur THEN the system SHALL provide detailed error context including device information and operation parameters
3. WHEN device access is denied THEN the system SHALL report permission and System Extension status information
4. WHEN diagnostic information is requested THEN the system SHALL provide device state, interface status, and recent error history
5. IF System Extension is not available THEN operations SHALL fail with clear System Extension status messaging

## Non-Functional Requirements

### Code Architecture and Modularity
- **Single Responsibility Principle**: Each IOKit integration file handles one specific USB operation type (control, bulk, interrupt, isochronous)
- **Protocol Conformance**: All implementations must conform to existing USBDeviceCommunicator protocol without breaking changes
- **Error Handling**: Consistent error mapping from IOKit return codes to project error types
- **Resource Management**: Automatic cleanup of IOKit references using Swift's deinit and RAII patterns

### Performance
- **Transfer Latency**: USB operations should complete within sub-50ms for typical local transfers
- **Memory Efficiency**: IOKit buffer management should minimize data copying and memory allocation
- **Concurrent Operations**: Support multiple concurrent USB transfers without blocking
- **Resource Cleanup**: Immediate release of IOKit resources when operations complete or fail

### Security
- **Device Access Control**: All device access must go through System Extension authorization
- **Buffer Validation**: Input validation for all USB transfer parameters and data buffers
- **Permission Checking**: Verify device claiming permissions before allowing USB operations
- **Error Information**: Prevent information leakage through error messages while maintaining debugging utility

### Reliability
- **Graceful Degradation**: Handle IOKit failures without crashing the USB/IP server
- **Recovery Mechanisms**: Automatic recovery from transient device disconnection scenarios
- **State Consistency**: Maintain accurate device binding state across System Extension communication
- **Operation Atomicity**: Ensure USB operations complete fully or fail cleanly without partial states

### Usability
- **Clear Error Messages**: Provide actionable error messages for common failure scenarios
- **Status Reporting**: Comprehensive device and operation status available through CLI commands
- **Integration Consistency**: Maintain compatibility with existing CLI command structure and output formatting