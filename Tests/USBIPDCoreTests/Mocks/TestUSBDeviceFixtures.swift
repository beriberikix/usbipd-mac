// TestUSBDeviceFixtures.swift
// Test fixtures with known USB device properties and scenarios

import Foundation
import IOKit.usb
@testable import USBIPDCore

// MARK: - Test Device Fixtures

/// Collection of test USB device fixtures for various testing scenarios
public struct TestUSBDeviceFixtures {
    
    // MARK: - Standard Test Devices
    
    /// Apple Magic Mouse - typical consumer device
    public static let appleMagicMouse = MockUSBDevice(
        vendorID: 0x05ac,
        productID: 0x030d,
        deviceClass: 0x03, // HID
        deviceSubClass: 0x01, // Boot Interface
        deviceProtocol: 0x02, // Mouse
        speed: 0, // Low speed
        manufacturerString: "Apple Inc.",
        productString: "Magic Mouse",
        serialNumberString: "ABC123456789",
        locationID: 0x14100000
    )
    
    /// Logitech USB Keyboard - another common HID device
    public static let logitechKeyboard = MockUSBDevice(
        vendorID: 0x046d,
        productID: 0xc31c,
        deviceClass: 0x03, // HID
        deviceSubClass: 0x01, // Boot Interface
        deviceProtocol: 0x01, // Keyboard
        speed: 0, // Low speed
        manufacturerString: "Logitech",
        productString: "USB Receiver",
        serialNumberString: nil, // No serial number
        locationID: 0x14200000
    )
    
    /// SanDisk USB Flash Drive - mass storage device
    public static let sandiskFlashDrive = MockUSBDevice(
        vendorID: 0x0781,
        productID: 0x5567,
        deviceClass: 0x08, // Mass Storage
        deviceSubClass: 0x06, // SCSI
        deviceProtocol: 0x50, // Bulk-Only Transport
        speed: 2, // High speed
        manufacturerString: "SanDisk",
        productString: "Cruzer Blade",
        serialNumberString: "4C530001071205117433",
        locationID: 0x14300000
    )
    
    /// Arduino Uno - CDC device
    public static let arduinoUno = MockUSBDevice(
        vendorID: 0x2341,
        productID: 0x0043,
        deviceClass: 0x02, // CDC
        deviceSubClass: 0x00,
        deviceProtocol: 0x00,
        speed: 1, // Full speed
        manufacturerString: "Arduino LLC",
        productString: "Arduino Uno",
        serialNumberString: "85736323838351F0E1E1",
        locationID: 0x14400000
    )
    
    /// USB Hub - hub device
    public static let usbHub = MockUSBDevice(
        vendorID: 0x0424,
        productID: 0x2514,
        deviceClass: 0x09, // Hub
        deviceSubClass: 0x00,
        deviceProtocol: 0x01, // Single TT
        speed: 2, // High speed
        manufacturerString: "Standard Microsystems Corp.",
        productString: "USB 2.0 Hub",
        serialNumberString: nil,
        locationID: 0x14500000
    )
    
    /// USB 3.0 External Hard Drive - SuperSpeed device
    public static let usb3ExternalDrive = MockUSBDevice(
        vendorID: 0x1058,
        productID: 0x25a2,
        deviceClass: 0x08, // Mass Storage
        deviceSubClass: 0x06, // SCSI
        deviceProtocol: 0x50, // Bulk-Only Transport
        speed: 3, // SuperSpeed
        manufacturerString: "Western Digital",
        productString: "My Passport 25A2",
        serialNumberString: "575834314539383936383537",
        locationID: 0x14600000
    )
    
    // MARK: - Error Scenario Devices
    
    /// Device with missing vendor ID (should cause error)
    public static let deviceMissingVendorID = MockUSBDevice(
        vendorID: 0x1234,
        productID: 0x5678,
        missingProperties: [kUSBVendorID]
    )
    
    /// Device with missing product ID (should cause error)
    public static let deviceMissingProductID = MockUSBDevice(
        vendorID: 0x1234,
        productID: 0x5678,
        missingProperties: [kUSBProductID]
    )
    
    /// Device with invalid vendor ID type (should cause error)
    public static let deviceInvalidVendorIDType = MockUSBDevice(
        vendorID: 0x1234,
        productID: 0x5678,
        invalidTypeProperties: [kUSBVendorID]
    )
    
    /// Device with invalid product ID type (should cause error)
    public static let deviceInvalidProductIDType = MockUSBDevice(
        vendorID: 0x1234,
        productID: 0x5678,
        invalidTypeProperties: [kUSBProductID]
    )
    
    /// Device with missing optional properties (should work with defaults)
    public static let deviceMissingOptionalProperties = MockUSBDevice(
        vendorID: 0x1234,
        productID: 0x5678,
        missingProperties: [kUSBDeviceClass, kUSBDeviceSubClass, kUSBDeviceProtocol, "Speed"]
    )
    
    /// Device with no string descriptors (should work with nil values)
    public static let deviceNoStringDescriptors = MockUSBDevice(
        vendorID: 0x1234,
        productID: 0x5678,
        manufacturerString: nil,
        productString: nil,
        serialNumberString: nil
    )
    
    // MARK: - Edge Case Devices
    
    /// Device with very long strings
    public static let deviceLongStrings = MockUSBDevice(
        vendorID: 0x1234,
        productID: 0x5678,
        manufacturerString: "Very Long Manufacturer Name That Exceeds Normal Length Expectations",
        productString: "Very Long Product Name That Also Exceeds Normal Length Expectations",
        serialNumberString: "VeryLongSerialNumberThatExceedsNormalLengthExpectations123456789"
    )
    
    /// Device with special characters in strings
    public static let deviceSpecialCharacters = MockUSBDevice(
        vendorID: 0x1234,
        productID: 0x5678,
        manufacturerString: "Manufacturer™ & Co. (Special)",
        productString: "Product® with Ümlauts & Spëcial Chars",
        serialNumberString: "SN-123/456_789@ABC"
    )
    
    /// Device with zero values
    public static let deviceZeroValues = MockUSBDevice(
        vendorID: 0x0000,
        productID: 0x0000,
        deviceClass: 0x00,
        deviceSubClass: 0x00,
        deviceProtocol: 0x00,
        speed: 255, // Unknown speed (invalid value)
        locationID: 0x00000000
    )
    
    /// Device with maximum values
    public static let deviceMaxValues = MockUSBDevice(
        vendorID: 0xFFFF,
        productID: 0xFFFF,
        deviceClass: 0xFF,
        deviceSubClass: 0xFF,
        deviceProtocol: 0xFF,
        speed: 3, // SuperSpeed (max supported)
        locationID: 0xFFFFFFFF
    )
    
    // MARK: - Test Scenarios
    
    /// Standard device collection for normal operation testing
    public static let standardDevices: [MockUSBDevice] = [
        appleMagicMouse,
        logitechKeyboard,
        sandiskFlashDrive,
        arduinoUno
    ]
    
    /// Mixed device collection with various types and speeds
    public static let mixedDevices: [MockUSBDevice] = [
        appleMagicMouse,
        sandiskFlashDrive,
        usbHub,
        usb3ExternalDrive
    ]
    
    /// Error scenario devices for testing error handling
    public static let errorDevices: [MockUSBDevice] = [
        deviceMissingVendorID,
        deviceMissingProductID,
        deviceInvalidVendorIDType,
        deviceInvalidProductIDType
    ]
    
    /// Edge case devices for robustness testing
    public static let edgeCaseDevices: [MockUSBDevice] = [
        deviceMissingOptionalProperties,
        deviceNoStringDescriptors,
        deviceLongStrings,
        deviceSpecialCharacters,
        deviceZeroValues,
        deviceMaxValues
    ]
    
    /// Empty device list for testing no devices scenario
    public static let noDevices: [MockUSBDevice] = []
    
    /// Single device for simple testing
    public static let singleDevice: [MockUSBDevice] = [appleMagicMouse]
    
    /// Large device collection for performance testing
    public static let largeDeviceCollection: [MockUSBDevice] = {
        var devices: [MockUSBDevice] = []
        
        // Add multiple copies of standard devices with different location IDs
        for i in 0..<50 {
            let locationID = UInt32(0x14000000 + (i * 0x100000))
            
            devices.append(MockUSBDevice(
                vendorID: 0x05ac,
                productID: 0x030d,
                deviceClass: 0x03,
                deviceSubClass: 0x01,
                deviceProtocol: 0x02,
                speed: 0,
                manufacturerString: "Apple Inc.",
                productString: "Magic Mouse \(i)",
                serialNumberString: "ABC\(String(format: "%06d", i))",
                locationID: locationID
            ))
        }
        
        return devices
    }()
}

// MARK: - Test Scenario Helpers

/// Helper methods for creating test scenarios
public extension TestUSBDeviceFixtures {
    
    /// Create a custom device with specific properties for testing
    static func customDevice(
        vendorID: UInt16 = 0x1234,
        productID: UInt16 = 0x5678,
        deviceClass: UInt8 = 0x09,
        deviceSubClass: UInt8 = 0x00,
        deviceProtocol: UInt8 = 0x00,
        speed: UInt8 = 1,
        manufacturerString: String? = "Test Manufacturer",
        productString: String? = "Test Product",
        serialNumberString: String? = "TEST123456",
        locationID: UInt32 = 0x14000000,
        missingProperties: Set<String> = [],
        invalidTypeProperties: Set<String> = []
    ) -> MockUSBDevice {
        return MockUSBDevice(
            vendorID: vendorID,
            productID: productID,
            deviceClass: deviceClass,
            deviceSubClass: deviceSubClass,
            deviceProtocol: deviceProtocol,
            speed: speed,
            manufacturerString: manufacturerString,
            productString: productString,
            serialNumberString: serialNumberString,
            locationID: locationID,
            missingProperties: missingProperties,
            invalidTypeProperties: invalidTypeProperties
        )
    }
    
    /// Create a device collection with specific bus/device ID patterns
    static func devicesWithIDs(count: Int, startingBusID: Int = 1) -> [MockUSBDevice] {
        var devices: [MockUSBDevice] = []
        
        for i in 0..<count {
            let busID = startingBusID + (i / 10) // 10 devices per bus
            let deviceID = (i % 10) + 1
            let locationID = UInt32((busID << 24) | deviceID)
            
            devices.append(MockUSBDevice(
                vendorID: UInt16(0x1000 + i),
                productID: UInt16(0x2000 + i),
                manufacturerString: "Manufacturer \(i)",
                productString: "Product \(i)",
                serialNumberString: "SN\(String(format: "%06d", i))",
                locationID: locationID
            ))
        }
        
        return devices
    }
}

// MARK: - Expected USBDevice Results

/// Expected USBDevice results for test fixtures
public extension TestUSBDeviceFixtures {
    
    /// Convert MockUSBDevice to expected USBDevice result
    static func expectedUSBDevice(from mockDevice: MockUSBDevice) -> USBDevice {
        let busID = String((mockDevice.locationID >> 24) & 0xFF)
        let deviceID = String(mockDevice.locationID & 0xFF)
        
        let speed: USBSpeed
        switch mockDevice.speed {
        case 0: speed = .low
        case 1: speed = .full
        case 2: speed = .high
        case 3: speed = .superSpeed
        default: speed = .unknown
        }
        
        return USBDevice(
            busID: busID,
            deviceID: deviceID,
            vendorID: mockDevice.vendorID,
            productID: mockDevice.productID,
            deviceClass: mockDevice.deviceClass,
            deviceSubClass: mockDevice.deviceSubClass,
            deviceProtocol: mockDevice.deviceProtocol,
            speed: speed,
            manufacturerString: mockDevice.manufacturerString,
            productString: mockDevice.productString,
            serialNumberString: mockDevice.serialNumberString
        )
    }
    
    /// Get expected USBDevice results for a collection of mock devices
    static func expectedUSBDevices(from mockDevices: [MockUSBDevice]) -> [USBDevice] {
        return mockDevices.map { expectedUSBDevice(from: $0) }
    }
}