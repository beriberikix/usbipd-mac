# Requirements Document

## Introduction

The System Extension Integration feature implements macOS System Extension functionality to provide reliable, privileged access to USB devices for the usbipd-mac USB/IP server. This feature addresses the critical gap between device discovery and actual device claiming, enabling exclusive access to USB devices for sharing over the network. The System Extension operates as a privileged background service that can claim USB devices from other drivers and provide secure communication channels between the CLI interface and kernel-level USB operations.

## Alignment with Product Vision

This feature directly supports multiple key objectives from product.md:

- **System Extensions Integration**: Fulfills the documented requirement for "reliable device access and claiming through macOS System Extensions"
- **Developer Productivity**: Eliminates the friction developers face when USB devices remain claimed by other processes, preventing effective USB/IP sharing
- **Docker Integration**: Essential foundation for enabling USB device access from Docker containers on macOS by providing exclusive device control
- **Platform Parity**: Brings macOS functionality closer to Linux USB/IP implementations that have kernel-level device control capabilities
- **Production Ready**: Addresses reliability and error handling requirements by providing proper device lifecycle management through system-level integration

## Requirements

### Requirement 1

**User Story:** As a developer using usbipd-mac, I want the system to reliably claim USB devices when I bind them, so that they can be exclusively shared over USB/IP without interference from other applications.

#### Acceptance Criteria

1. WHEN a USB device is bound using `usbipd bind <busid>` THEN the System Extension SHALL claim exclusive access to that device
2. IF a device is already in use by another driver THEN the System Extension SHALL attempt to unbind the existing driver and claim the device
3. WHEN a device claim succeeds THEN the System Extension SHALL notify the main daemon of successful device acquisition
4. WHEN a device claim fails THEN the System Extension SHALL return a specific error code indicating the failure reason
5. IF a bound device is disconnected THEN the System Extension SHALL release the claim and notify the daemon of device removal

### Requirement 2

**User Story:** As a system administrator, I want the System Extension to handle macOS security requirements properly, so that the USB/IP functionality works within macOS security boundaries.

#### Acceptance Criteria

1. WHEN the System Extension is installed THEN it SHALL request appropriate system permissions through macOS authorization dialogs
2. IF System Extension approval is denied THEN the system SHALL provide clear guidance on enabling the extension through System Preferences
3. WHEN the System Extension starts THEN it SHALL validate its entitlements and permissions before attempting device operations
4. IF permission requirements are not met THEN the System Extension SHALL log specific error messages indicating missing capabilities
5. WHEN communicating with the main daemon THEN the System Extension SHALL use secure IPC mechanisms with proper authentication

### Requirement 3

**User Story:** As a user of the USB/IP client, I want device operations to be handled reliably by the System Extension, so that USB device sharing works consistently without manual intervention.

#### Acceptance Criteria

1. WHEN a client connects to request a device THEN the System Extension SHALL verify the device is properly claimed before allowing access
2. IF multiple clients attempt to access the same device THEN the System Extension SHALL enforce exclusive access rules
3. WHEN a client disconnects THEN the System Extension SHALL maintain device claim until explicitly unbound
4. WHEN the daemon restarts THEN the System Extension SHALL restore device claims for all previously bound devices
5. IF the System Extension crashes THEN it SHALL automatically restart and restore previous device claim states

### Requirement 4

**User Story:** As a developer debugging USB/IP issues, I want comprehensive logging and status information from the System Extension, so that I can troubleshoot device access problems effectively.

#### Acceptance Criteria

1. WHEN System Extension operations occur THEN it SHALL log device claim/release events with timestamps and device identifiers
2. IF errors occur during device operations THEN the System Extension SHALL log detailed error information including IOKit error codes
3. WHEN requested by the CLI THEN the System Extension SHALL provide current status of all claimed devices
4. WHEN device state changes occur THEN the System Extension SHALL log state transitions for debugging purposes
5. IF System Extension is queried for status THEN it SHALL return information about its health, claimed devices, and any error conditions

## Non-Functional Requirements

### Code Architecture and Modularity
- **Single Responsibility Principle**: System Extension code should focus solely on device claiming and IPC communication, with separate modules for IOKit integration, device lifecycle management, and daemon communication
- **Modular Design**: Create isolated components for device claiming, permission management, IPC handling, and logging that can be independently tested and maintained
- **Dependency Management**: Minimize dependencies on external frameworks beyond IOKit, Foundation, and SystemExtension frameworks
- **Clear Interfaces**: Define clean contracts between the System Extension and main daemon using well-defined IPC protocols and data structures

### Performance
- Device claiming operations must complete within 2 seconds under normal conditions
- System Extension startup time must not exceed 5 seconds
- Memory usage should remain under 10MB during normal operation
- IPC communication latency between daemon and extension should be under 100ms

### Security
- System Extension must operate within macOS sandboxing restrictions
- All IPC communications must use authenticated channels
- Device access must be limited to explicitly bound devices only
- Extension must validate all incoming requests and parameters
- Logging must not expose sensitive system information

### Reliability
- System Extension must automatically recover from IOKit errors
- Device claim state must be persistent across System Extension restarts
- Extension must handle device disconnection/reconnection gracefully
- Error conditions must not leave devices in an unusable state
- Extension must provide health monitoring and status reporting capabilities

### Usability
- Installation process must provide clear instructions for System Extension approval
- Error messages must be actionable and user-friendly
- Status information must be accessible through CLI commands
- Extension must integrate seamlessly with existing usbipd commands
- Troubleshooting information must be easily accessible through logs and status commands