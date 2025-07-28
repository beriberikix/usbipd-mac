# Design Document

## Overview

The IOKit device discovery implementation provides USB device enumeration and monitoring capabilities for the usbipd-mac project. This design implements the existing `DeviceDiscovery` protocol using macOS IOKit framework to discover, monitor, and provide information about connected USB devices.

The implementation focuses on read-only device discovery without device claiming, providing the foundation for CLI operations and future USB/IP protocol implementation. The design emphasizes proper IOKit memory management, thread safety, and integration with the existing logging and error handling infrastructure.

## Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    CLI Commands                              │
│              (list, bind, unbind)                           │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│                ServerCoordinator                            │
│            (Device event handling)                          │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│              DeviceDiscovery Protocol                       │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│            IOKitDeviceDiscovery                             │
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │   Device        │  │   Device        │  │   Device    │ │
│  │  Enumeration    │  │   Monitoring    │  │   Lookup    │ │
│  └─────────────────┘  └─────────────────┘  └─────────────┘ │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│                   IOKit Framework                           │
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │  IOService      │  │  IONotification │  │  IORegistry │ │
│  │   Matching      │  │     Port        │  │   Iterator  │ │
│  └─────────────────┘  └─────────────────┘  └─────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Component Relationships

- **IOKitDeviceDiscovery**: Main implementation class conforming to DeviceDiscovery protocol
- **Device Enumeration**: Discovers all connected USB devices using IOServiceMatching
- **Device Monitoring**: Monitors device connect/disconnect events using IOKit notifications
- **Device Lookup**: Finds specific devices by bus/device ID
- **IOKit Integration**: Direct interface with macOS IOKit framework

## Components and Interfaces

### IOKitDeviceDiscovery Class

```swift
public class IOKitDeviceDiscovery: DeviceDiscovery {
    // MARK: - Properties
    private let logger: Logger
    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var isMonitoring: Bool = false
    private let queue: DispatchQueue
    
    // MARK: - DeviceDiscovery Protocol
    public var onDeviceConnected: ((USBDevice) -> Void)?
    public var onDeviceDisconnected: ((USBDevice) -> Void)?
    
    // MARK: - Public Methods
    public func discoverDevices() throws -> [USBDevice]
    public func getDevice(busID: String, deviceID: String) throws -> USBDevice?
    public func startNotifications() throws
    public func stopNotifications()
}
```

### Device Enumeration Component

**Purpose**: Discover all connected USB devices and convert IOKit properties to USBDevice objects.

**Key Functions**:
- `discoverDevices()`: Main enumeration function
- `createUSBDeviceFromService(_:)`: Convert IOKit service to USBDevice
- `extractDeviceProperties(_:)`: Extract device properties from IOKit
- `generateBusAndDeviceIDs(_:)`: Create USB/IP compatible device IDs

**IOKit Integration**:
- Uses `IOServiceMatching(kIOUSBDeviceClassName)` to find USB devices
- Iterates through services using `IOServiceGetMatchingServices`
- Extracts properties using `IORegistryEntryCreateCFProperties`

### Device Monitoring Component

**Purpose**: Monitor USB device connect/disconnect events and trigger callbacks.

**Key Functions**:
- `startNotifications()`: Set up IOKit notification system
- `stopNotifications()`: Clean up notification resources
- `deviceAddedCallback(_:_:)`: Handle device connection events
- `deviceRemovedCallback(_:_:)`: Handle device disconnection events

**IOKit Integration**:
- Uses `IONotificationPortCreate` for notification port
- Registers for `kIOFirstMatchNotification` and `kIOTerminatedNotification`
- Runs notification port on dedicated dispatch queue

### Device Lookup Component

**Purpose**: Find specific devices by bus and device ID for bind/unbind operations.

**Key Functions**:
- `getDevice(busID:deviceID:)`: Find device by ID
- `matchesDeviceID(_:busID:deviceID:)`: Check if device matches IDs
- `getCurrentDevices()`: Get current device list for lookup

## Data Models

### USBDevice Structure

The existing `USBDevice` struct will be populated with IOKit data:

```swift
public struct USBDevice: USBDeviceInfo {
    public let busID: String          // Generated from IOKit location
    public let deviceID: String       // Generated from IOKit address
    public let vendorID: UInt16       // kUSBVendorID
    public let productID: UInt16      // kUSBProductID
    public let deviceClass: UInt8     // kUSBDeviceClass
    public let deviceSubClass: UInt8  // kUSBDeviceSubClass
    public let deviceProtocol: UInt8  // kUSBDeviceProtocol
    public let speed: USBSpeed        // kUSBDeviceSpeed
    public let manufacturerString: String?  // kUSBManufacturerStringIndex
    public let productString: String?       // kUSBProductStringIndex
    public let serialNumberString: String?  // kUSBSerialNumberStringIndex
}
```

### IOKit Property Mapping

| USBDevice Property | IOKit Property Key | Type | Notes |
|-------------------|-------------------|------|-------|
| vendorID | kUSBVendorID | CFNumber | Required |
| productID | kUSBProductID | CFNumber | Required |
| deviceClass | kUSBDeviceClass | CFNumber | Required |
| deviceSubClass | kUSBDeviceSubClass | CFNumber | Required |
| deviceProtocol | kUSBDeviceProtocol | CFNumber | Required |
| speed | kUSBDeviceSpeed | CFNumber | Map to USBSpeed enum |
| manufacturerString | kUSBManufacturerStringIndex | CFString | Optional |
| productString | kUSBProductStringIndex | CFString | Optional |
| serialNumberString | kUSBSerialNumberStringIndex | CFString | Optional |

### Bus/Device ID Generation

Since IOKit doesn't directly provide USB/IP compatible bus/device IDs, we'll generate them:

```swift
// Bus ID: Extract from locationID (high 24 bits)
let busID = String((locationID >> 24) & 0xFF)

// Device ID: Extract from locationID (low 8 bits) 
let deviceID = String(locationID & 0xFF)
```

## Error Handling

### Error Types

The implementation will use existing error types from `Common/Errors.swift`:

```swift
public enum DeviceDiscoveryError: Error {
    case ioKitError(Int32, String)
    case deviceNotFound(String)
    case accessDenied(String)
    case initializationFailed(String)
}
```

### Error Scenarios

1. **IOKit Service Access Failure**: When `IOServiceGetMatchingServices` fails
2. **Property Extraction Failure**: When device properties cannot be read
3. **Memory Allocation Failure**: When IOKit object creation fails
4. **Notification Setup Failure**: When notification port cannot be created
5. **Permission Denied**: When app lacks USB device access permissions

### Error Handling Strategy

- **Graceful Degradation**: Continue processing other devices when one fails
- **Detailed Logging**: Log IOKit error codes and descriptions
- **Resource Cleanup**: Always release IOKit objects even on error
- **User-Friendly Messages**: Convert IOKit errors to descriptive messages

## Testing Strategy

### Unit Tests

**IOKitDeviceDiscoveryTests.swift**:
- Test device enumeration with mock IOKit services
- Test property extraction and USBDevice creation
- Test error handling for various failure scenarios
- Test notification setup and cleanup
- Test device lookup functionality

**Mock Strategy**:
- Create protocol wrapper around IOKit functions for testing
- Use dependency injection to provide mock IOKit interface
- Test with simulated device connect/disconnect events

### Integration Tests

**Device Discovery Integration**:
- Test with real USB devices (if available in CI environment)
- Test notification system with actual device events
- Validate device ID generation consistency
- Test memory management and resource cleanup

### Test Data

Create test fixtures with known USB device properties:
```swift
struct TestUSBDevice {
    static let mockKeyboard = USBDevice(
        busID: "1", deviceID: "2",
        vendorID: 0x05ac, productID: 0x024f,
        deviceClass: 3, deviceSubClass: 1, deviceProtocol: 1,
        speed: .full,
        manufacturerString: "Apple Inc.",
        productString: "Apple Internal Keyboard",
        serialNumberString: nil
    )
}
```

## Implementation Considerations

### Thread Safety

- Use dedicated `DispatchQueue` for IOKit operations
- Ensure callback invocations are thread-safe
- Protect shared state with appropriate synchronization

### Memory Management

- Always call `IOObjectRelease()` for IOKit objects
- Use RAII pattern with defer statements for cleanup
- Monitor for memory leaks in IOKit integration

### Performance

- Cache device list to avoid repeated IOKit queries
- Use efficient data structures for device lookup
- Minimize IOKit calls in notification handlers

### macOS Compatibility

- Target macOS 11.0+ (as specified in Package.swift)
- Handle deprecated IOKit APIs gracefully
- Test on multiple macOS versions if possible

### Logging Integration

- Use existing Logger infrastructure with appropriate log levels
- Log IOKit error codes and descriptions for debugging
- Include device information in log context

### Error Recovery

- Implement retry logic for transient IOKit failures
- Gracefully handle device removal during enumeration
- Maintain monitoring functionality even if individual operations fail