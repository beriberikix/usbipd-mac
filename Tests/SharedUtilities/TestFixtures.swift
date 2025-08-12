// TestFixtures.swift
// Standardized test fixture generation for USB devices, server configurations, and System Extension data
// This consolidates test data creation from existing test files into a shared infrastructure

import Foundation
import IOKit.usb
@testable import USBIPDCore
@testable import USBIPDCLI
@testable import Common

// MARK: - USB Device Test Fixtures

/// Comprehensive collection of USB device test fixtures for various testing scenarios
public struct USBDeviceTestFixtures {
    
    // MARK: - Standard Test Devices
    
    /// Apple Magic Mouse - typical consumer HID device
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
    
    /// Logitech USB Keyboard - common HID device
    public static let logitechKeyboard = MockUSBDevice(
        vendorID: 0x046d,
        productID: 0xc31c,
        deviceClass: 0x03, // HID
        deviceSubClass: 0x01, // Boot Interface
        deviceProtocol: 0x01, // Keyboard
        speed: 0, // Low speed
        manufacturerString: "Logitech",
        productString: "USB Receiver",
        serialNumberString: nil,
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
    
    // MARK: - Device Collections
    
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
        usb3ExternalDrive
    ]
    
    /// Single device for simple testing
    public static let singleDevice: [MockUSBDevice] = [appleMagicMouse]
    
    /// Empty device list for testing no devices scenario
    public static let noDevices: [MockUSBDevice] = []
    
    // MARK: - Device Creation Helpers
    
    /// Create a custom device with specific properties for testing
    public static func customDevice(
        vendorID: UInt16 = 0x1234,
        productID: UInt16 = 0x5678,
        deviceClass: UInt8 = 0x09,
        deviceSubClass: UInt8 = 0x00,
        deviceProtocol: UInt8 = 0x00,
        speed: UInt8 = 1,
        manufacturerString: String? = "Test Manufacturer",
        productString: String? = "Test Product",
        serialNumberString: String? = "TEST123456",
        locationID: UInt32 = 0x14000000
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
            locationID: locationID
        )
    }
    
    /// Convert MockUSBDevice to expected USBDevice result
    public static func expectedUSBDevice(from mockDevice: MockUSBDevice) -> USBDevice {
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
    public static func expectedUSBDevices(from mockDevices: [MockUSBDevice]) -> [USBDevice] {
        return mockDevices.map { expectedUSBDevice(from: $0) }
    }
}

// MARK: - Server Configuration Test Fixtures

/// Server configuration test fixtures for various testing scenarios
public struct ServerConfigTestFixtures {
    
    /// Default server configuration for basic testing
    public static let defaultConfig = ServerConfig()
    
    /// Development server configuration with debug settings
    public static let developmentConfig = ServerConfig(
        port: 3240,
        logLevel: .debug,
        debugMode: true,
        maxConnections: 5,
        connectionTimeout: 15.0,
        allowedDevices: [],
        autoBindDevices: false,
        logFilePath: nil
    )
    
    /// Production server configuration with strict settings
    public static let productionConfig = ServerConfig(
        port: 3240,
        logLevel: .warning,
        debugMode: false,
        maxConnections: 20,
        connectionTimeout: 60.0,
        allowedDevices: ["1-1", "1-2"],
        autoBindDevices: true,
        logFilePath: "/var/log/usbipd.log"
    )
    
    /// CI server configuration optimized for automated testing
    public static let ciConfig = ServerConfig(
        port: 3241,
        logLevel: .info,
        debugMode: false,
        maxConnections: 10,
        connectionTimeout: 30.0,
        allowedDevices: [],
        autoBindDevices: false,
        logFilePath: nil
    )
    
    /// Test configuration with custom values
    public static let customTestConfig = ServerConfig(
        port: 3245,
        logLevel: .debug,
        debugMode: true,
        maxConnections: 15,
        connectionTimeout: 45.0,
        allowedDevices: ["test-device-1", "test-device-2"],
        autoBindDevices: true,
        logFilePath: "/tmp/test-log.log"
    )
    
    /// Create a temporary server configuration file for testing
    public static func createTemporaryConfig(_ config: ServerConfig = defaultConfig) throws -> String {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let configPath = tempDir.appendingPathComponent("test-config-\(UUID().uuidString).json").path
        try config.save(to: configPath)
        return configPath
    }
}

// MARK: - CLI Test Fixtures

/// CLI component test fixtures and mock objects
public struct CLITestFixtures {
    
    /// Mock device discovery for testing
    public static func createMockDeviceDiscovery(
        devices: [USBDevice] = [],
        shouldThrowError: Bool = false
    ) -> MockDeviceDiscovery {
        let mock = MockDeviceDiscovery()
        mock.mockDevices = devices
        mock.shouldThrowError = shouldThrowError
        return mock
    }
    
    /// Mock USB/IP server for testing
    public static func createMockUSBIPServer(
        shouldThrowError: Bool = false,
        isRunning: Bool = false
    ) -> MockUSBIPServer {
        let mock = MockUSBIPServer()
        mock.shouldThrowError = shouldThrowError
        mock.isServerRunning = isRunning
        return mock
    }
    
    /// Mock output formatter for testing
    public static func createMockOutputFormatter() -> MockOutputFormatter {
        return MockOutputFormatter()
    }
}

// MARK: - System Extension Test Fixtures

/// System Extension test fixtures and configuration data
public struct SystemExtensionTestFixtures {
    
    /// Test bundle configuration for System Extension
    public static let testBundleConfig = SystemExtensionBundleConfig(
        bundleIdentifier: "com.example.usbipd.test",
        bundleName: "Test USBIPD System Extension",
        bundleVersion: "1.0.0",
        buildVersion: "1",
        teamIdentifier: "TESTTEAM123",
        codeSigningIdentity: "Test Developer",
        capabilities: ["com.apple.developer.system-extension.install"]
    )
    
    /// Mock System Extension IOKit service for testing
    public static func createMockIOKitService(
        claimableDevices: Set<io_service_t> = [],
        alreadyClaimedDevices: Set<io_service_t> = [],
        deviceClaimErrors: [io_service_t: kern_return_t] = [:]
    ) -> MockSystemExtensionIOKit {
        let mock = MockSystemExtensionIOKit()
        mock.claimableDevices = claimableDevices
        mock.alreadyClaimedDevices = alreadyClaimedDevices
        mock.deviceClaimErrors = deviceClaimErrors
        return mock
    }
    
    /// Test System Extension installation data
    public static let testInstallationData = SystemExtensionInstallationData(
        bundlePath: "/tmp/test-extension.systemextension",
        identifier: "com.example.usbipd.test",
        teamIdentifier: "TESTTEAM123",
        codeSignature: "valid-test-signature"
    )
}

// MARK: - Test Environment Data

/// Common test environment data and utilities
public struct TestEnvironmentFixtures {
    
    /// Temporary directory creation for tests
    public static func createTemporaryDirectory() -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let testDir = tempDir.appendingPathComponent("usbipd-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true, attributes: nil)
        return testDir
    }
    
    /// Clean up temporary directory
    public static func cleanupTemporaryDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
    
    /// Create temporary log file for testing
    public static func createTemporaryLogFile() throws -> String {
        let tempDir = createTemporaryDirectory()
        let logFile = tempDir.appendingPathComponent("test.log")
        try "".write(to: logFile, atomically: true, encoding: .utf8)
        return logFile.path
    }
    
    /// Common test timeouts
    public static let shortTimeout: TimeInterval = 1.0
    public static let mediumTimeout: TimeInterval = 5.0
    public static let longTimeout: TimeInterval = 15.0
}

// MARK: - Protocol Test Fixtures

/// USB/IP protocol message test fixtures
public struct ProtocolTestFixtures {
    
    /// Standard USB/IP protocol version
    public static let standardProtocolVersion: UInt16 = 0x0111
    
    /// Test device import request
    public static let testDeviceImportRequest = USBIPDeviceImportRequest(
        version: standardProtocolVersion,
        command: 0x8003,
        status: 0,
        busid: "1-1"
    )
    
    /// Test device list request
    public static let testDeviceListRequest = USBIPDeviceListRequest(
        version: standardProtocolVersion,
        command: 0x8005,
        status: 0
    )
    
    /// Create a test USB/IP device description
    public static func createDeviceDescription(
        for device: USBDevice,
        busnum: UInt32 = 1,
        devnum: UInt32 = 1
    ) -> USBIPDeviceDescription {
        return USBIPDeviceDescription(
            path: "/sys/devices/platform/\(device.busID)-\(device.deviceID)",
            busid: "\(device.busID)-\(device.deviceID)",
            busnum: busnum,
            devnum: devnum,
            speed: USBIPSpeed(from: device.speed),
            idVendor: device.vendorID,
            idProduct: device.productID,
            bcdDevice: 0x0100,
            bDeviceClass: device.deviceClass,
            bDeviceSubClass: device.deviceSubClass,
            bDeviceProtocol: device.deviceProtocol,
            bConfigurationValue: 1,
            bNumConfigurations: 1,
            bNumInterfaces: 1
        )
    }
}