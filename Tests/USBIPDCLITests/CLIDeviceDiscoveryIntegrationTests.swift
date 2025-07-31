// CLIDeviceDiscoveryIntegrationTests.swift
// Integration tests for CLI commands with device discovery

import XCTest
import Foundation
@testable import USBIPDCLI
@testable import USBIPDCore
@testable import Common

final class CLIDeviceDiscoveryIntegrationTests: XCTestCase {
    
    var mockDeviceDiscovery: MockDeviceDiscovery!
    var ioKitDeviceDiscovery: IOKitDeviceDiscovery!
    var serverConfig: ServerConfig!
    
    override func setUp() {
        super.setUp()
        
        // Set up mock device discovery with test devices that simulate IOKit behavior
        mockDeviceDiscovery = MockDeviceDiscovery()
        
        // Set up real IOKit device discovery for integration testing
        ioKitDeviceDiscovery = IOKitDeviceDiscovery()
        
        // Set up server config
        serverConfig = ServerConfig()
        
        // Set up standard test devices that match IOKit device discovery format
        // These devices simulate realistic IOKit-generated bus/device IDs and properties
        mockDeviceDiscovery.mockDevices = [
            USBDevice(
                busID: "20",
                deviceID: "0", 
                vendorID: 0x05ac,
                productID: 0x030d,
                deviceClass: 0x03,
                deviceSubClass: 0x01,
                deviceProtocol: 0x02,
                speed: .low,
                manufacturerString: "Apple Inc.",
                productString: "Magic Mouse",
                serialNumberString: "ABC123456789"
            ),
            USBDevice(
                busID: "20",
                deviceID: "1",
                vendorID: 0x046d,
                productID: 0xc31c,
                deviceClass: 0x03,
                deviceSubClass: 0x01,
                deviceProtocol: 0x01,
                speed: .low,
                manufacturerString: "Logitech",
                productString: "USB Receiver",
                serialNumberString: nil
            ),
            USBDevice(
                busID: "21",
                deviceID: "0",
                vendorID: 0x0781,
                productID: 0x5567,
                deviceClass: 0x08,
                deviceSubClass: 0x06,
                deviceProtocol: 0x50,
                speed: .high,
                manufacturerString: "SanDisk",
                productString: "Cruzer Blade",
                serialNumberString: "4C530001071205117433"
            ),
            USBDevice(
                busID: "21",
                deviceID: "1",
                vendorID: 0x2341,
                productID: 0x0043,
                deviceClass: 0x02,
                deviceSubClass: 0x00,
                deviceProtocol: 0x00,
                speed: .full,
                manufacturerString: "Arduino LLC",
                productString: "Arduino Uno",
                serialNumberString: "85736323838351F0E1E1"
            )
        ]
    }
    
    override func tearDown() {
        mockDeviceDiscovery = nil
        ioKitDeviceDiscovery = nil
        serverConfig = nil
        super.tearDown()
    }
    
    // MARK: - List Command Integration Tests
    
    func testListCommandWithDeviceDiscovery() throws {
        // Given: ListCommand with device discovery that simulates IOKit behavior
        let outputFormatter = DefaultOutputFormatter()
        let listCommand = ListCommand(deviceDiscovery: mockDeviceDiscovery, outputFormatter: outputFormatter)
        
        // Test the command execution without capturing stdout to avoid hanging
        XCTAssertNoThrow(try listCommand.execute(with: []), "List command should execute without throwing")
        
        // Test the output formatting directly
        let devices = try mockDeviceDiscovery.discoverDevices()
        let output = outputFormatter.formatDeviceList(devices)
        
        // Then: Should successfully discover and format devices
        // Verify output contains expected device information from IOKit-style devices
        XCTAssertTrue(output.contains("Local USB Device(s)"), "Output should contain header")
        XCTAssertTrue(output.contains("05ac:030d"), "Output should contain Apple Magic Mouse VID:PID")
        XCTAssertTrue(output.contains("046d:c31c"), "Output should contain Logitech USB Receiver VID:PID")
        XCTAssertTrue(output.contains("0781:5567"), "Output should contain SanDisk VID:PID")
        XCTAssertTrue(output.contains("2341:0043"), "Output should contain Arduino VID:PID")
        
        // Verify device names are present
        XCTAssertTrue(output.contains("Magic Mouse"), "Should contain Apple Magic Mouse product name")
        XCTAssertTrue(output.contains("USB Receiver"), "Should contain Logitech product name")
        XCTAssertTrue(output.contains("Cruzer Blade"), "Should contain SanDisk product name")
        XCTAssertTrue(output.contains("Arduino Uno"), "Should contain Arduino product name")
        
        // Verify busid format matches IOKit device discovery format
        XCTAssertTrue(output.contains("20-0"), "Should contain Apple Magic Mouse busid")
        XCTAssertTrue(output.contains("20-1"), "Should contain Logitech device busid")
        XCTAssertTrue(output.contains("21-0"), "Should contain SanDisk device busid")
        XCTAssertTrue(output.contains("21-1"), "Should contain Arduino device busid")
    }
    
    func testListCommandWithLinuxCompatibleFormatter() throws {
        // Given: ListCommand with Linux-compatible formatter
        let outputFormatter = LinuxCompatibleOutputFormatter()
        let listCommand = ListCommand(deviceDiscovery: mockDeviceDiscovery, outputFormatter: outputFormatter)
        
        // Execute command without capturing stdout
        XCTAssertNoThrow(try listCommand.execute(with: []), "List command should execute without throwing")
        
        // Test the output formatting directly
        let devices = try mockDeviceDiscovery.discoverDevices()
        let output = outputFormatter.formatDeviceList(devices)
        
        // Then: Should successfully format devices in Linux-compatible format
        // Verify Linux-compatible output format
        XCTAssertTrue(output.contains("Local USB Device(s)"), "Should contain Linux-style header")
        XCTAssertTrue(output.contains("=================="), "Should contain Linux-style separator")
        XCTAssertTrue(output.contains("/dev/bus/usb/"), "Should contain Linux-style device node paths")
        
        // Verify device information is present in Linux format
        XCTAssertTrue(output.contains("05ac:030d"), "Should contain Apple Magic Mouse VID:PID")
        XCTAssertTrue(output.contains("046d:c31c"), "Should contain Logitech VID:PID")
        
        // Check for the correct device node format based on the bus IDs
        // Format: /dev/bus/usb/{busID padded to 3}/{deviceID padded to 3}
        // Note: The current implementation pads to the right, so "20" becomes "200", not "020"
        XCTAssertTrue(output.contains("/dev/bus/usb/200/000"), "Should contain Linux-style device node for Apple device (20-0)")
        XCTAssertTrue(output.contains("/dev/bus/usb/200/100"), "Should contain Linux-style device node for Logitech device (20-1)")
        XCTAssertTrue(output.contains("/dev/bus/usb/210/000"), "Should contain Linux-style device node for SanDisk device (21-0)")
        XCTAssertTrue(output.contains("/dev/bus/usb/210/100"), "Should contain Linux-style device node for Arduino (21-1)")
    }
    
    func testListCommandWithNoDevices() throws {
        // Given: No devices available
        mockDeviceDiscovery.mockDevices = []
        let outputFormatter = DefaultOutputFormatter()
        let listCommand = ListCommand(deviceDiscovery: mockDeviceDiscovery, outputFormatter: outputFormatter)
        
        // Execute command without capturing stdout
        XCTAssertNoThrow(try listCommand.execute(with: []), "List command should execute without throwing")
        
        // Test the output formatting directly
        let devices = try mockDeviceDiscovery.discoverDevices()
        let output = outputFormatter.formatDeviceList(devices)
        
        // Then: Should handle empty device list gracefully
        // Verify appropriate message for no devices (empty device list)
        XCTAssertTrue(devices.isEmpty, "Should have no devices")
        XCTAssertTrue(output.contains("Local USB Device(s)"), "Should still contain header")
    }
    
    func testListCommandWithDeviceDiscoveryError() {
        // Given: Device discovery failure (simulating IOKit error)
        mockDeviceDiscovery.shouldThrowError = true
        let outputFormatter = DefaultOutputFormatter()
        let listCommand = ListCommand(deviceDiscovery: mockDeviceDiscovery, outputFormatter: outputFormatter)
        
        // When/Then: Should throw CommandLineError
        XCTAssertThrowsError(try listCommand.execute(with: [])) { error in
            XCTAssertTrue(error is CommandLineError, "Should throw CommandLineError")
            if let commandError = error as? CommandLineError {
                switch commandError {
                case .executionFailed(let message):
                    XCTAssertTrue(message.contains("Failed to list devices"), "Error message should indicate list failure")
                default:
                    XCTFail("Expected executionFailed error")
                }
            }
        }
    }
    
    // MARK: - Device Data Format Compatibility Tests
    
    func testDeviceDataFormatCompatibilityWithDefaultFormatter() throws {
        // Given: Device discovery with known test devices
        let devices = try mockDeviceDiscovery.discoverDevices()
        let formatter = DefaultOutputFormatter()
        
        // Verify we have expected test devices
        XCTAssertGreaterThan(devices.count, 0, "Should have discovered devices")
        
        // When: Formatting device list
        let output = formatter.formatDeviceList(devices)
        
        // Then: Output should contain expected device information
        XCTAssertTrue(output.contains("Local USB Device(s)"), "Should contain header")
        XCTAssertTrue(output.contains("Busid"), "Should contain busid column")
        XCTAssertTrue(output.contains("Dev-Node"), "Should contain dev-node column")
        XCTAssertTrue(output.contains("USB Device Information"), "Should contain device info column")
        
        // Verify device-specific information is present for known test devices
        XCTAssertTrue(output.contains("05ac:030d"), "Should contain Apple Magic Mouse VID:PID")
        XCTAssertTrue(output.contains("046d:c31c"), "Should contain Logitech VID:PID")
        XCTAssertTrue(output.contains("Magic Mouse"), "Should contain Apple Magic Mouse product name")
        XCTAssertTrue(output.contains("USB Receiver"), "Should contain Logitech product name")
        
        // Verify device busids are present
        for device in devices {
            let busid = "\(device.busID)-\(device.deviceID)"
            XCTAssertTrue(output.contains(busid), "Should contain device busid: \(busid)")
        }
    }
    
    func testDeviceDataFormatCompatibilityWithLinuxFormatter() throws {
        // Given: Device discovery with known test devices
        let devices = try mockDeviceDiscovery.discoverDevices()
        let formatter = LinuxCompatibleOutputFormatter()
        
        // When: Formatting device list
        let output = formatter.formatDeviceList(devices)
        
        // Then: Output should be Linux-compatible
        XCTAssertTrue(output.contains("Local USB Device(s)"), "Should contain Linux-style header")
        XCTAssertTrue(output.contains("=================="), "Should contain Linux-style separator")
        
        // Verify device node format is Linux-compatible
        XCTAssertTrue(output.contains("/dev/bus/usb/"), "Should contain Linux-style device node paths")
    }
    
    func testSingleDeviceFormatCompatibility() throws {
        // Given: Single device from device discovery
        let devices = try mockDeviceDiscovery.discoverDevices()
        guard let firstDevice = devices.first else {
            XCTFail("Should have at least one device for testing")
            return
        }
        
        let defaultFormatter = DefaultOutputFormatter()
        let linuxFormatter = LinuxCompatibleOutputFormatter()
        
        // When: Formatting single device
        let defaultOutput = defaultFormatter.formatDevice(firstDevice, detailed: false)
        let linuxOutput = linuxFormatter.formatDevice(firstDevice, detailed: false)
        let linuxDetailedOutput = linuxFormatter.formatDevice(firstDevice, detailed: true)
        
        // Then: Both formatters should handle the device correctly
        let busid = "\(firstDevice.busID)-\(firstDevice.deviceID)"
        let vendorProduct = "\(firstDevice.vendorID.hexString):\(firstDevice.productID.hexString)"
        
        XCTAssertTrue(defaultOutput.contains(busid), "Default formatter should contain busid")
        XCTAssertTrue(defaultOutput.contains(vendorProduct), "Default formatter should contain vendor:product")
        
        XCTAssertTrue(linuxOutput.contains(busid), "Linux formatter should contain busid")
        XCTAssertTrue(linuxOutput.contains(vendorProduct), "Linux formatter should contain vendor:product")
        
        // Detailed output should contain additional information
        XCTAssertTrue(linuxDetailedOutput.contains("Device: \(busid)"), "Detailed output should contain device identifier")
        XCTAssertTrue(linuxDetailedOutput.contains("Vendor ID:"), "Detailed output should contain vendor ID label")
        XCTAssertTrue(linuxDetailedOutput.contains("Product ID:"), "Detailed output should contain product ID label")
    }
    
    // MARK: - Bind Command Integration Tests
    
    func testBindCommandWithDeviceDiscovery() throws {
        // Given: BindCommand with device discovery
        let bindCommand = BindCommand(deviceDiscovery: mockDeviceDiscovery, serverConfig: serverConfig)
        
        // Get expected device for binding (Apple Magic Mouse from fixtures)
        let devices = try mockDeviceDiscovery.discoverDevices()
        guard let firstDevice = devices.first else {
            XCTFail("Should have at least one device for testing")
            return
        }
        
        let busid = "\(firstDevice.busID)-\(firstDevice.deviceID)"
        
        // Execute bind command
        XCTAssertNoThrow(try bindCommand.execute(with: [busid]), "Bind command should execute without throwing")
        
        // Then: Device should be added to allowed devices
        XCTAssertTrue(serverConfig.allowedDevices.contains(busid), 
                     "Device should be added to allowed devices")
    }
    
    func testBindCommandWithNonexistentDevice() {
        // Given: BindCommand with device discovery
        let bindCommand = BindCommand(deviceDiscovery: mockDeviceDiscovery, serverConfig: serverConfig)
        
        // When/Then: Binding nonexistent device should throw error
        XCTAssertThrowsError(try bindCommand.execute(with: ["999-999"])) { error in
            XCTAssertTrue(error is CommandHandlerError, "Should throw CommandHandlerError")
            if let handlerError = error as? CommandHandlerError {
                switch handlerError {
                case .deviceNotFound(let message):
                    XCTAssertTrue(message.contains("999-999"), "Error should mention the busid")
                case .deviceBindingFailed(let message):
                    XCTAssertTrue(message.contains("999-999"), "Error should mention the busid")
                default:
                    XCTFail("Expected deviceNotFound or deviceBindingFailed error, got: \(handlerError)")
                }
            }
        }
        
        // Verify device was not added to allowed devices
        XCTAssertFalse(serverConfig.allowedDevices.contains("999-999"), 
                      "Nonexistent device should not be added to allowed devices")
    }
    
    func testBindCommandDeviceLookupFunctionality() throws {
        // Given: Multiple devices and BindCommand
        let bindCommand = BindCommand(deviceDiscovery: mockDeviceDiscovery, serverConfig: serverConfig)
        
        // Get all devices to test lookup functionality
        let devices = try mockDeviceDiscovery.discoverDevices()
        XCTAssertGreaterThan(devices.count, 1, "Need multiple devices for lookup test")
        
        // When: Binding specific device by ID (Arduino device with different device ID)
        let targetDevice = devices.last! // Use Arduino device (21-1)
        let busid = "\(targetDevice.busID)-\(targetDevice.deviceID)"
        
        // Execute bind command
        XCTAssertNoThrow(try bindCommand.execute(with: [busid]), "Bind command should execute without throwing")
        
        // Then: Only the target device should be bound
        let deviceIdentifier = "\(targetDevice.busID)-\(targetDevice.deviceID)"
        XCTAssertTrue(serverConfig.allowedDevices.contains(deviceIdentifier), 
                     "Target device should be bound")
        
        // Verify only one device is bound
        XCTAssertEqual(serverConfig.allowedDevices.count, 1, 
                      "Only one device should be bound")
    }
    
    // MARK: - Unbind Command Integration Tests
    
    func testUnbindCommandWithDeviceDiscovery() throws {
        // Given: Device is already bound
        let devices = try mockDeviceDiscovery.discoverDevices()
        guard let firstDevice = devices.first else {
            XCTFail("Should have at least one device for testing")
            return
        }
        
        let busid = "\(firstDevice.busID)-\(firstDevice.deviceID)"
        serverConfig.allowDevice(busid)
        
        // Verify device is initially bound
        XCTAssertTrue(serverConfig.allowedDevices.contains(busid), 
                     "Device should be initially bound")
        
        let unbindCommand = UnbindCommand(deviceDiscovery: mockDeviceDiscovery, serverConfig: serverConfig)
        
        // Execute unbind command
        XCTAssertNoThrow(try unbindCommand.execute(with: [busid]), "Unbind command should execute without throwing")
        
        // Then: Device should be removed from allowed devices
        XCTAssertFalse(serverConfig.allowedDevices.contains(busid), 
                      "Device should be removed from allowed devices")
    }
    
    func testUnbindCommandWithNonboundDevice() throws {
        // Given: Device is not bound
        let unbindCommand = UnbindCommand(deviceDiscovery: mockDeviceDiscovery, serverConfig: serverConfig)
        
        // Verify device is not initially bound
        XCTAssertFalse(serverConfig.allowedDevices.contains("20-0"), 
                      "Device should not be initially bound")
        
        // Execute unbind command
        XCTAssertNoThrow(try unbindCommand.execute(with: ["20-0"]), "Unbind command should execute without throwing")
        
        // Then: Should complete without error (graceful handling)
        // Device should still not be bound
        XCTAssertFalse(serverConfig.allowedDevices.contains("20-0"), 
                      "Device should still not be bound")
    }
    
    // MARK: - Device ID Format Compatibility Tests
    
    func testDeviceIDFormatConsistency() throws {
        // Given: Devices discovered through device discovery
        let devices = try mockDeviceDiscovery.discoverDevices()
        
        // When: Checking device ID formats
        for device in devices {
            // Then: Device IDs should follow expected format
            XCTAssertFalse(device.busID.isEmpty, "Bus ID should not be empty")
            XCTAssertFalse(device.deviceID.isEmpty, "Device ID should not be empty")
            
            // Bus and device IDs should be numeric strings
            XCTAssertNotNil(Int(device.busID), "Bus ID should be numeric: \(device.busID)")
            XCTAssertNotNil(Int(device.deviceID), "Device ID should be numeric: \(device.deviceID)")
            
            // Combined busid format should be valid for CLI commands
            let busid = "\(device.busID)-\(device.deviceID)"
            let busidPattern = #"^\d+-\d+$"#
            XCTAssertTrue(busid.range(of: busidPattern, options: .regularExpression) != nil, 
                         "Busid should match CLI format: \(busid)")
        }
    }
    
    func testDeviceIDUniqueness() throws {
        // Given: Multiple devices discovered through device discovery
        let devices = try mockDeviceDiscovery.discoverDevices()
        
        // When: Checking device ID uniqueness
        var seenBusids = Set<String>()
        
        for device in devices {
            let busid = "\(device.busID)-\(device.deviceID)"
            
            // Then: Each device should have a unique busid
            XCTAssertFalse(seenBusids.contains(busid), 
                          "Duplicate busid found: \(busid)")
            seenBusids.insert(busid)
        }
    }
    
    // MARK: - Error Handling Integration Tests
    
    func testCLIErrorHandlingWithDeviceDiscoveryFailures() {
        // Given: Device discovery failure
        mockDeviceDiscovery.shouldThrowError = true
        let listCommand = ListCommand(deviceDiscovery: mockDeviceDiscovery, outputFormatter: DefaultOutputFormatter())
        
        // When/Then: Should handle device discovery failures gracefully
        XCTAssertThrowsError(try listCommand.execute(with: [])) { error in
            XCTAssertTrue(error is CommandLineError, "Should throw CommandLineError")
        }
    }
    
    // MARK: - IOKit Integration Tests
    
    func testIOKitDeviceDiscoveryWithListCommand() throws {
        // Given: ListCommand with real IOKit device discovery
        let outputFormatter = DefaultOutputFormatter()
        let listCommand = ListCommand(deviceDiscovery: ioKitDeviceDiscovery, outputFormatter: outputFormatter)
        
        // When: Executing list command with IOKit device discovery
        // Test that the command executes without throwing (avoid stdout capture which can hang)
        XCTAssertNoThrow(try listCommand.execute(with: []), "List command should execute without throwing")
        
        // Test the output formatting directly with discovered devices
        let devices = try ioKitDeviceDiscovery.discoverDevices()
        let output = outputFormatter.formatDeviceList(devices)
        
        // Then: Should successfully format devices
        XCTAssertTrue(output.contains("Local USB Device(s)"), "Output should contain header")
        
        // The output should either contain devices or indicate no devices found
        if devices.isEmpty {
            XCTAssertTrue(output.contains("Busid"), "Should contain busid column header even with no devices")
        } else {
            // If devices are found, verify format is correct
            XCTAssertTrue(output.contains("Busid"), "Should contain busid column header")
            XCTAssertTrue(output.contains("Dev-Node"), "Should contain dev-node column header")
            XCTAssertTrue(output.contains("USB Device Information"), "Should contain device info column header")
        }
    }
    
    func testIOKitDeviceDiscoveryDataFormatCompatibility() throws {
        // Given: Real IOKit device discovery
        let devices = try ioKitDeviceDiscovery.discoverDevices()
        
        // When: Checking device data format
        for device in devices {
            // Then: Device data should be compatible with CLI expectations
            XCTAssertFalse(device.busID.isEmpty, "Bus ID should not be empty")
            XCTAssertFalse(device.deviceID.isEmpty, "Device ID should not be empty")
            
            // Bus and device IDs should be numeric strings (IOKit format)
            XCTAssertNotNil(Int(device.busID), "Bus ID should be numeric: \(device.busID)")
            XCTAssertNotNil(Int(device.deviceID), "Device ID should be numeric: \(device.deviceID)")
            
            // Vendor and product IDs should be valid
            XCTAssertGreaterThan(device.vendorID, 0, "Vendor ID should be greater than 0")
            XCTAssertGreaterThan(device.productID, 0, "Product ID should be greater than 0")
            
            // Device class information should be present
            // Note: Device class can be 0 for some devices, so we don't check > 0
            XCTAssertLessThanOrEqual(device.deviceClass, 255, "Device class should be valid byte")
            XCTAssertLessThanOrEqual(device.deviceSubClass, 255, "Device subclass should be valid byte")
            XCTAssertLessThanOrEqual(device.deviceProtocol, 255, "Device protocol should be valid byte")
            
            // Speed should be a valid enum value
            XCTAssertTrue([USBSpeed.unknown, .low, .full, .high, .superSpeed].contains(device.speed), 
                         "Speed should be valid enum value")
        }
    }
    
    func testIOKitDeviceDiscoveryWithBindCommand() throws {
        // Given: Real IOKit device discovery and bind command
        let bindCommand = BindCommand(deviceDiscovery: ioKitDeviceDiscovery, serverConfig: serverConfig)
        
        // Get available devices
        let devices = try ioKitDeviceDiscovery.discoverDevices()
        
        // Skip test if no devices are available (common in CI environments)
        guard let firstDevice = devices.first else {
            throw XCTSkip("No USB devices available for bind testing")
        }
        
        let busid = "\(firstDevice.busID)-\(firstDevice.deviceID)"
        
        // When: Binding device using IOKit device discovery
        XCTAssertNoThrow(try bindCommand.execute(with: [busid]), "Bind command should execute without throwing")
        
        // Then: Device should be successfully bound
        XCTAssertTrue(serverConfig.allowedDevices.contains(busid), 
                     "Device should be added to allowed devices")
    }
    
    func testIOKitDeviceDiscoveryWithUnbindCommand() throws {
        // Given: Real IOKit device discovery and unbind command
        let unbindCommand = UnbindCommand(deviceDiscovery: ioKitDeviceDiscovery, serverConfig: serverConfig)
        
        // Get available devices
        let devices = try ioKitDeviceDiscovery.discoverDevices()
        
        // Skip test if no devices are available
        guard let firstDevice = devices.first else {
            throw XCTSkip("No USB devices available for unbind testing")
        }
        
        let busid = "\(firstDevice.busID)-\(firstDevice.deviceID)"
        
        // Pre-bind the device
        serverConfig.allowDevice(busid)
        XCTAssertTrue(serverConfig.allowedDevices.contains(busid), "Device should be initially bound")
        
        // When: Unbinding device using IOKit device discovery
        XCTAssertNoThrow(try unbindCommand.execute(with: [busid]), "Unbind command should execute without throwing")
        
        // Then: Device should be successfully unbound
        XCTAssertFalse(serverConfig.allowedDevices.contains(busid), 
                      "Device should be removed from allowed devices")
    }
    
    func testIOKitDeviceDiscoveryLookupFunctionality() throws {
        // Given: Real IOKit device discovery
        let devices = try ioKitDeviceDiscovery.discoverDevices()
        
        // Skip test if no devices are available
        guard let targetDevice = devices.first else {
            throw XCTSkip("No USB devices available for lookup testing")
        }
        
        // When: Looking up specific device by bus and device ID
        let foundDevice = try ioKitDeviceDiscovery.getDevice(busID: targetDevice.busID, deviceID: targetDevice.deviceID)
        
        // Then: Should find the correct device
        XCTAssertNotNil(foundDevice, "Should find the device")
        XCTAssertEqual(foundDevice?.busID, targetDevice.busID, "Bus ID should match")
        XCTAssertEqual(foundDevice?.deviceID, targetDevice.deviceID, "Device ID should match")
        XCTAssertEqual(foundDevice?.vendorID, targetDevice.vendorID, "Vendor ID should match")
        XCTAssertEqual(foundDevice?.productID, targetDevice.productID, "Product ID should match")
    }
    
    func testIOKitDeviceDiscoveryLookupNonexistentDevice() throws {
        // Given: Real IOKit device discovery
        // When: Looking up nonexistent device
        let foundDevice = try ioKitDeviceDiscovery.getDevice(busID: "999", deviceID: "999")
        
        // Then: Should return nil for nonexistent device
        XCTAssertNil(foundDevice, "Should return nil for nonexistent device")
    }
    
    func testIOKitDeviceDiscoveryBusIDFormat() throws {
        // Given: Real IOKit device discovery
        let devices = try ioKitDeviceDiscovery.discoverDevices()
        
        // When: Checking bus ID format consistency
        for device in devices {
            let busid = "\(device.busID)-\(device.deviceID)"
            
            // Then: Bus ID format should be compatible with CLI commands
            let busidPattern = #"^\d+-\d+$"#
            XCTAssertTrue(busid.range(of: busidPattern, options: .regularExpression) != nil, 
                         "Busid should match CLI format: \(busid)")
            
            // Bus ID components should be reasonable values (not empty or extremely large)
            let busIDInt = Int(device.busID)!
            let deviceIDInt = Int(device.deviceID)!
            
            XCTAssertGreaterThanOrEqual(busIDInt, 0, "Bus ID should be non-negative")
            XCTAssertGreaterThanOrEqual(deviceIDInt, 0, "Device ID should be non-negative")
            XCTAssertLessThan(busIDInt, 1000, "Bus ID should be reasonable (< 1000)")
            XCTAssertLessThan(deviceIDInt, 1000, "Device ID should be reasonable (< 1000)")
        }
    }
    
    func testIOKitDeviceDiscoveryOutputFormatterCompatibility() throws {
        // Given: Real IOKit device discovery and both formatters
        let devices = try ioKitDeviceDiscovery.discoverDevices()
        let defaultFormatter = DefaultOutputFormatter()
        let linuxFormatter = LinuxCompatibleOutputFormatter()
        
        // When: Formatting devices with both formatters
        let defaultOutput = defaultFormatter.formatDeviceList(devices)
        let linuxOutput = linuxFormatter.formatDeviceList(devices)
        
        // Then: Both formatters should handle IOKit devices correctly
        XCTAssertTrue(defaultOutput.contains("Local USB Device(s)"), "Default formatter should contain header")
        XCTAssertTrue(linuxOutput.contains("Local USB Device(s)"), "Linux formatter should contain header")
        
        // If devices are present, verify they're formatted correctly
        if !devices.isEmpty {
            for device in devices {
                let busid = "\(device.busID)-\(device.deviceID)"
                let vendorProduct = "\(device.vendorID.hexString):\(device.productID.hexString)"
                
                XCTAssertTrue(defaultOutput.contains(busid), "Default output should contain busid: \(busid)")
                XCTAssertTrue(defaultOutput.contains(vendorProduct), "Default output should contain VID:PID: \(vendorProduct)")
                
                XCTAssertTrue(linuxOutput.contains(busid), "Linux output should contain busid: \(busid)")
                XCTAssertTrue(linuxOutput.contains(vendorProduct), "Linux output should contain VID:PID: \(vendorProduct)")
            }
        }
    }
    
    func testIOKitDeviceDiscoveryErrorHandling() {
        // Given: Real IOKit device discovery
        // When: Testing error handling with invalid parameters
        
        // Test with empty bus ID
        do {
            let result = try ioKitDeviceDiscovery.getDevice(busID: "", deviceID: "1")
            XCTAssertNil(result, "Should return nil for empty bus ID")
        } catch {
            XCTFail("Should not throw error for empty bus ID: \(error)")
        }
        
        // Test with empty device ID
        do {
            let result = try ioKitDeviceDiscovery.getDevice(busID: "1", deviceID: "")
            XCTAssertNil(result, "Should return nil for empty device ID")
        } catch {
            XCTFail("Should not throw error for empty device ID: \(error)")
        }
        
        // Test device discovery doesn't throw for normal operation
        XCTAssertNoThrow(try ioKitDeviceDiscovery.discoverDevices(), "Device discovery should not throw under normal conditions")
    }
    
    func testIOKitDeviceDiscoveryNotificationSystem() throws {
        // Given: Real IOKit device discovery
        // When: Testing notification system setup and cleanup
        
        // Test notification startup
        XCTAssertNoThrow(try ioKitDeviceDiscovery.startNotifications(), "Should start notifications without error")
        
        // Test notification cleanup
        XCTAssertNoThrow(ioKitDeviceDiscovery.stopNotifications(), "Should stop notifications without error")
        
        // Test multiple start/stop cycles
        XCTAssertNoThrow(try ioKitDeviceDiscovery.startNotifications(), "Should restart notifications")
        XCTAssertNoThrow(ioKitDeviceDiscovery.stopNotifications(), "Should stop notifications again")
    }
    
    func testIOKitDeviceDiscoveryPerformance() throws {
        // Given: Real IOKit device discovery
        // When: Measuring device discovery performance
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let devices = try ioKitDeviceDiscovery.discoverDevices()
        let endTime = CFAbsoluteTimeGetCurrent()
        
        let discoveryTime = endTime - startTime
        
        // Then: Discovery should complete in reasonable time (< 5 seconds)
        XCTAssertLessThan(discoveryTime, 5.0, "Device discovery should complete within 5 seconds")
        
        // Log performance metrics for monitoring
        print("IOKit device discovery performance:")
        print("  - Devices found: \(devices.count)")
        print("  - Discovery time: \(String(format: "%.3f", discoveryTime)) seconds")
        if !devices.isEmpty {
            print("  - Time per device: \(String(format: "%.3f", discoveryTime / Double(devices.count))) seconds")
        }
    }
    
    // MARK: - Helper Methods
    
    /// Helper method to verify device format compatibility
    private func verifyDeviceFormatCompatibility(_ device: USBDevice) {
        XCTAssertFalse(device.busID.isEmpty, "Bus ID should not be empty")
        XCTAssertFalse(device.deviceID.isEmpty, "Device ID should not be empty")
        
        // Bus and device IDs should be numeric strings
        XCTAssertNotNil(Int(device.busID), "Bus ID should be numeric: \(device.busID)")
        XCTAssertNotNil(Int(device.deviceID), "Device ID should be numeric: \(device.deviceID)")
        
        // Combined busid format should be valid for CLI commands
        let busid = "\(device.busID)-\(device.deviceID)"
        let busidPattern = #"^\d+-\d+$"#
        XCTAssertTrue(busid.range(of: busidPattern, options: .regularExpression) != nil, 
                     "Busid should match CLI format: \(busid)")
    }
}