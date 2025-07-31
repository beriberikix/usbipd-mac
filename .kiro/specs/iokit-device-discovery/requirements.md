# Requirements Document

## Introduction

This feature implements IOKit-based USB device discovery for the usbipd-mac project. Currently, the project has a well-defined protocol interface for device discovery (`DeviceDiscovery` protocol) and a placeholder implementation (`IOKitDeviceDiscovery`), but no actual IOKit integration. This implementation will provide the foundation for all USB device operations in the USB/IP server, enabling real device enumeration, monitoring, and lookup functionality that the CLI and server components depend on.

The IOKit device discovery is critical because it serves as the data source for the `usbipd list` command, provides device information for configuration management (bind/unbind tracking), and supplies the device data needed for future USB/IP protocol implementation. This implementation focuses on device discovery and monitoring only - actual device claiming and exclusive access will be implemented later through System Extensions.

**Scope Note:** This implementation does NOT include device claiming or exclusive access control. It provides read-only device information and monitoring. Device binding in this context refers only to configuration management (tracking which devices are marked as shareable), not actual device claiming from the system.

## Requirements

### Requirement 1

**User Story:** As a developer using the usbipd CLI, I want to see all connected USB devices when I run `usbipd list`, so that I can identify which devices are available for sharing.

#### Acceptance Criteria

1. WHEN the user runs `usbipd list` THEN the system SHALL display all currently connected USB devices
2. WHEN a USB device is connected to the system THEN the device SHALL appear in the device list with complete information
3. WHEN the device discovery encounters an IOKit error THEN the system SHALL log the error and continue processing other devices
4. WHEN no USB devices are connected THEN the system SHALL display an appropriate "no devices found" message
5. WHEN the system lacks permissions to access USB devices THEN the system SHALL provide a clear error message explaining the permission requirements

### Requirement 2

**User Story:** As a developer, I want each discovered USB device to include comprehensive device information, so that I can properly identify and work with specific devices.

#### Acceptance Criteria

1. WHEN a USB device is discovered THEN the system SHALL extract the vendor ID (VID) from IOKit properties
2. WHEN a USB device is discovered THEN the system SHALL extract the product ID (PID) from IOKit properties
3. WHEN a USB device is discovered THEN the system SHALL extract device class, subclass, and protocol information
4. WHEN a USB device is discovered THEN the system SHALL extract string descriptors (manufacturer, product, serial number) when available
5. WHEN a USB device is discovered THEN the system SHALL determine the device speed (low, full, high, super speed)
6. WHEN a USB device is discovered THEN the system SHALL assign appropriate bus ID and device ID values for USB/IP compatibility
7. WHEN string descriptors are not available THEN the system SHALL handle missing values gracefully with nil values

### Requirement 3

**User Story:** As a system administrator, I want the USB/IP server to automatically detect when USB devices are connected or disconnected, so that the device list stays current without manual refresh.

#### Acceptance Criteria

1. WHEN device monitoring is started THEN the system SHALL register for IOKit device connection notifications
2. WHEN device monitoring is started THEN the system SHALL register for IOKit device disconnection notifications
3. WHEN a USB device is connected THEN the system SHALL trigger the onDeviceConnected callback with device information
4. WHEN a USB device is disconnected THEN the system SHALL trigger the onDeviceDisconnected callback with device information
5. WHEN device monitoring is stopped THEN the system SHALL properly clean up IOKit notification resources
6. WHEN the notification system encounters errors THEN the system SHALL log errors and attempt to maintain monitoring functionality
7. WHEN multiple devices are connected simultaneously THEN the system SHALL handle all notifications correctly without race conditions

### Requirement 4

**User Story:** As a developer using the bind/unbind commands, I want to look up specific USB devices by their bus and device IDs, so that I can identify devices for configuration management.

#### Acceptance Criteria

1. WHEN getDevice is called with valid bus ID and device ID THEN the system SHALL return the matching USBDevice object
2. WHEN getDevice is called with invalid bus ID or device ID THEN the system SHALL return nil
3. WHEN getDevice is called and the device is no longer connected THEN the system SHALL return nil
4. WHEN multiple devices exist THEN the system SHALL return only the device matching the specified IDs
5. WHEN the device lookup encounters IOKit errors THEN the system SHALL handle errors gracefully and return nil

**Note:** This lookup is for identification purposes only. Actual device claiming will be implemented later through System Extensions.

### Requirement 5

**User Story:** As a developer, I want the IOKit device discovery to integrate seamlessly with the existing architecture, so that it works with the current CLI commands and server infrastructure.

#### Acceptance Criteria

1. WHEN IOKitDeviceDiscovery is instantiated THEN it SHALL conform to the DeviceDiscovery protocol
2. WHEN discoverDevices() is called THEN it SHALL return an array of USBDevice objects matching the existing data structure
3. WHEN the implementation encounters errors THEN it SHALL throw appropriate DeviceDiscoveryError types
4. WHEN IOKit memory management is required THEN the system SHALL properly release all IOKit objects to prevent memory leaks
5. WHEN the implementation is used by ServerCoordinator THEN it SHALL work without requiring changes to existing server logic
6. WHEN the implementation is used by CLI commands THEN it SHALL provide data in the format expected by existing command handlers

### Requirement 6

**User Story:** As a system administrator, I want proper error handling and logging for device discovery operations, so that I can troubleshoot issues and understand system behavior.

#### Acceptance Criteria

1. WHEN IOKit operations fail THEN the system SHALL log detailed error information including IOKit error codes
2. WHEN device properties cannot be read THEN the system SHALL log warnings and continue with available information
3. WHEN memory allocation fails THEN the system SHALL handle the error gracefully and log the failure
4. WHEN device enumeration encounters unexpected device types THEN the system SHALL log the information and skip unsupported devices
5. WHEN notification setup fails THEN the system SHALL throw a DeviceDiscoveryError with descriptive error message
6. WHEN the system runs out of resources THEN the system SHALL clean up properly and report the resource limitation