# Requirements Document: USB Request/Response Protocol Implementation

## Introduction

The USB Request/Response Protocol Implementation feature extends the current usbipd-mac USB/IP server from a device enumeration-only demonstration to a fully functional USB device sharing system. This feature implements the core USB I/O forwarding mechanism that enables actual USB device communication over the network, transforming the project from an MVP proof-of-concept to a production-ready USB sharing solution.

Currently, the USB/IP server can discover USB devices and respond to device list requests from clients, but cannot handle actual USB operations (control transfers, bulk transfers, interrupt transfers, or isochronous transfers). This implementation will add the missing USB request/response handling that enables real USB device functionality over the network.

The feature implements the complete USB/IP protocol specification for USB request forwarding, including URB (USB Request Block) processing, USB transfer type handling, and integration with the existing IOKit-based device management layer through System Extension device claiming.

## Alignment with Product Vision

This feature directly supports several key objectives outlined in product.md:

- **Docker Integration**: Enables actual USB device functionality from Docker containers, not just device enumeration
- **Linux Kernel Compatibility**: Implements the complete protocol expected by Linux vhci-hcd.ko virtual HCI driver
- **Performance Oriented**: Provides the foundation for low-latency, high-throughput USB operations over network
- **Production Ready**: Transforms the current MVP into a reliable, production-capable USB sharing solution

The implementation establishes usbipd-mac as a genuine alternative to Linux-based USB/IP servers, enabling the project to achieve its vision of becoming the canonical USB/IP solution for macOS.

## Requirements

### Requirement 1: USB Request Processing Infrastructure

**User Story:** As a USB/IP server, I want to process incoming USB requests from clients, so that I can forward USB operations to claimed physical devices.

#### Acceptance Criteria

1. WHEN a USB/IP client sends a USBIP_CMD_SUBMIT request THEN the server SHALL decode the USB request parameters and prepare for device forwarding
2. WHEN the USB request contains invalid or malformed data THEN the server SHALL respond with appropriate USBIP_RET_SUBMIT error status
3. WHEN the USB request targets a device that is not claimed or available THEN the server SHALL respond with device not found error status
4. WHEN multiple concurrent USB requests are received THEN the server SHALL handle them concurrently without blocking other requests

### Requirement 2: USB Transfer Type Support

**User Story:** As a USB device client, I want to perform different types of USB transfers (control, bulk, interrupt, isochronous), so that I can use all USB device functionality over the network.

#### Acceptance Criteria

1. WHEN a control transfer request is received THEN the server SHALL process setup packet, data stage, and status stage according to USB specification
2. WHEN a bulk transfer request is received THEN the server SHALL handle large data transfers with appropriate timeout and error handling
3. WHEN an interrupt transfer request is received THEN the server SHALL process periodic data transfers with correct timing and buffering
4. WHEN an isochronous transfer request is received THEN the server SHALL handle time-critical transfers with minimum latency
5. IF a transfer type is not supported by the target device THEN the server SHALL respond with appropriate USB error code

### Requirement 3: USB Request Block (URB) Processing

**User Story:** As a USB/IP protocol implementation, I want to properly handle URB structures and lifecycle, so that USB operations are correctly forwarded and completed.

#### Acceptance Criteria

1. WHEN a USBIP_CMD_SUBMIT is received THEN the server SHALL extract URB parameters (endpoint, transfer type, buffer size, flags) accurately
2. WHEN the URB is processed by the USB device THEN the server SHALL capture completion status, actual transfer length, and error conditions
3. WHEN the URB processing completes THEN the server SHALL respond with USBIP_RET_SUBMIT containing status and any returned data
4. WHEN a USBIP_CMD_UNLINK request is received THEN the server SHALL attempt to cancel the specified pending URB and respond with USBIP_RET_UNLINK
5. IF multiple URBs are submitted concurrently THEN the server SHALL maintain proper URB tracking and respond to each URB individually

### Requirement 4: IOKit USB Interface Integration

**User Story:** As a USB device claiming system, I want to communicate with claimed USB devices through IOKit interfaces, so that USB requests can be executed on physical hardware.

#### Acceptance Criteria

1. WHEN a USB request needs to be forwarded to a claimed device THEN the server SHALL use the appropriate IOKit USB interface methods
2. WHEN the claimed device supports the requested endpoint and transfer type THEN the server SHALL configure the IOKit interface accordingly
3. WHEN IOKit operations complete THEN the server SHALL extract results (data, status, error codes) for USB/IP response formatting
4. IF the IOKit operation fails or times out THEN the server SHALL translate IOKit errors to appropriate USB error codes
5. WHEN device claiming status changes THEN the server SHALL reject new USB requests for unclaimed devices with appropriate error responses

### Requirement 5: Protocol Message Extensions

**User Story:** As a USB/IP protocol implementation, I want to support USBIP_CMD_SUBMIT and USBIP_CMD_UNLINK messages, so that clients can perform complete USB operations.

#### Acceptance Criteria

1. WHEN implementing USBIP_CMD_SUBMIT message parsing THEN the server SHALL correctly decode all URB fields (transfer_buffer_length, setup packet, transfer_flags)
2. WHEN implementing USBIP_RET_SUBMIT message creation THEN the server SHALL encode response with actual_length, status, error_count, and returned data
3. WHEN implementing USBIP_CMD_UNLINK message parsing THEN the server SHALL extract seqnum for URB cancellation
4. WHEN implementing USBIP_RET_UNLINK message creation THEN the server SHALL respond with unlink status and error information
5. WHEN message encoding/decoding errors occur THEN the server SHALL log detailed error information and close the client connection

### Requirement 6: Error Handling and Recovery

**User Story:** As a USB device sharing system, I want robust error handling for USB operations, so that client applications receive appropriate feedback and the server remains stable.

#### Acceptance Criteria

1. WHEN USB device errors occur (device not ready, endpoint stall, timeout) THEN the server SHALL translate to appropriate USB status codes
2. WHEN IOKit interface errors occur THEN the server SHALL map IOKit error codes to USB/IP protocol error responses
3. WHEN client connections are interrupted during USB operations THEN the server SHALL clean up pending URBs and release resources
4. WHEN System Extension device claiming fails THEN the server SHALL reject USB requests with clear error messages
5. IF the server encounters fatal errors during USB processing THEN the server SHALL log detailed diagnostic information and attempt graceful recovery

### Requirement 7: Performance and Concurrent Processing

**User Story:** As a USB device sharing system, I want efficient USB request processing, so that USB operations maintain acceptable performance over the network.

#### Acceptance Criteria

1. WHEN multiple USB requests are pending THEN the server SHALL process them concurrently using appropriate threading or async patterns
2. WHEN large bulk transfers are processed THEN the server SHALL optimize data copying and buffering to minimize latency
3. WHEN interrupt transfers require periodic processing THEN the server SHALL maintain timing requirements without blocking other operations
4. WHEN USB requests complete THEN the server SHALL respond to clients with minimal delay between IOKit completion and network transmission
5. IF system resources become constrained THEN the server SHALL prioritize critical USB operations and provide appropriate backpressure mechanisms

## Non-Functional Requirements

### Code Architecture and Modularity
- **Single Responsibility Principle**: USB request processing, IOKit integration, and protocol messaging should be in separate, focused modules
- **Modular Design**: USB transfer type handlers should be isolated and independently testable components
- **Dependency Management**: Clear interfaces between protocol layer, device layer, and IOKit integration
- **Clear Interfaces**: Well-defined contracts between request processor, device communication, and System Extension integration

### Performance
- **Latency Requirements**: USB control transfers shall complete within 100ms over local network under normal conditions
- **Throughput Requirements**: Bulk transfers shall achieve at least 80% of theoretical USB bandwidth limits
- **Concurrent Processing**: Support for at least 16 concurrent USB requests without degraded performance
- **Memory Efficiency**: USB request buffers shall be allocated and released promptly to minimize memory footprint

### Security
- **Input Validation**: All USB/IP protocol messages shall be validated before processing to prevent buffer overflows or protocol attacks
- **Device Access Control**: USB operations shall only be permitted on devices that are properly claimed through System Extension
- **Resource Limits**: USB request buffer sizes shall be limited to prevent memory exhaustion attacks
- **Error Information**: Error messages shall not leak sensitive system information or memory contents

### Reliability
- **Error Recovery**: USB request failures shall not crash the server or leave the system in an inconsistent state
- **Connection Resilience**: Client connection failures during USB operations shall be handled gracefully with proper cleanup
- **Device State Management**: USB device state shall remain consistent even when operations fail or are cancelled
- **System Integration**: Integration with existing device discovery and claiming systems shall not introduce instability

### Usability
- **Error Diagnostics**: Clear, actionable error messages for common USB operation failures and configuration issues
- **Logging Integration**: USB request processing shall integrate with existing logging system for debugging and monitoring
- **Status Reporting**: USB operation status shall be available through existing CLI status commands
- **Protocol Compatibility**: Full compatibility with existing USB/IP clients including Linux kernel vhci-hcd.ko driver