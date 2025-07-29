// CLIDeviceDiscoveryIntegrationTests.swift
// Integration tests for CLI commands with device discovery

import XCTest
import Foundation
@testable import USBIPDCLI
@testable import USBIPDCore
@testable import Common

final class CLIDeviceDiscoveryIntegrationTests: XCTestCase {
    
    var mockDeviceDiscovery: MockDeviceDiscovery!
    var serverConfig: ServerConfig!
    
    override func setUp() {
        super.setUp()
        
        // Set up mock device discovery with test devices that simulate IOKit behavior
        mockDeviceDiscovery = MockDeviceDiscovery()
        
        // Set up server config
        serverConfig = ServerConfig()
        
        // Set up standard test devices that match IOKit device discovery format
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
                deviceID: "0",
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
                busID: "20",
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
                busID: "20",
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
        serverConfig = nil
        super.tearDown()
    }
    
    // MARK: - List Command Integration Tests
    
    func testListCommandWithDeviceDiscovery() throws {
        // Given: ListCommand with device discovery that simulates IOKit behavior
        let outputFormatter = DefaultOutputFormatter()
        let listCommand = ListCommand(deviceDiscovery: mockDeviceDiscovery, outputFormatter: outputFormatter)
        
        // Capture output by redirecting stdout
        let output = try captureStdout {
            try listCommand.execute(with: [])
        }
        
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
        XCTAssertTrue(output.contains("20-0"), "Should contain device busids")
        XCTAssertTrue(output.contains("20-1"), "Should contain Arduino device busid")
    }
    
    func testListCommandWithLinuxCompatibleFormatter() throws {
        // Given: ListCommand with Linux-compatible formatter
        let outputFormatter = LinuxCompatibleOutputFormatter()
        let listCommand = ListCommand(deviceDiscovery: mockDeviceDiscovery, outputFormatter: outputFormatter)
        
        // Capture output
        let output = try captureStdout {
            try listCommand.execute(with: [])
        }
        
        // Then: Should successfully format devices in Linux-compatible format
        // Verify Linux-compatible output format
        XCTAssertTrue(output.contains("Local USB Device(s)"), "Should contain Linux-style header")
        XCTAssertTrue(output.contains("=================="), "Should contain Linux-style separator")
        XCTAssertTrue(output.contains("/dev/bus/usb/"), "Should contain Linux-style device node paths")
        
        // Verify device information is present in Linux format
        XCTAssertTrue(output.contains("05ac:030d"), "Should contain Apple Magic Mouse VID:PID")
        XCTAssertTrue(output.contains("046d:c31c"), "Should contain Logitech VID:PID")
        XCTAssertTrue(output.contains("/dev/bus/usb/020/000"), "Should contain Linux-style device node for devices")
        XCTAssertTrue(output.contains("/dev/bus/usb/020/001"), "Should contain Linux-style device node for Arduino")
    }
    
    func testListCommandWithNoDevices() throws {
        // Given: No devices available
        mockDeviceDiscovery.mockDevices = []
        let outputFormatter = DefaultOutputFormatter()
        let listCommand = ListCommand(deviceDiscovery: mockDeviceDiscovery, outputFormatter: outputFormatter)
        
        // Capture output
        let output = try captureStdout {
            try listCommand.execute(with: [])
        }
        
        // Then: Should handle empty device list gracefully
        // Verify appropriate message for no devices
        XCTAssertTrue(output.contains("No USB devices found"), "Should display no devices message")
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
        
        // Capture output
        let output = try captureStdout {
            try bindCommand.execute(with: [busid])
        }
        
        // Then: Device should be added to allowed devices
        XCTAssertTrue(serverConfig.allowedDevices.contains(busid), 
                     "Device should be added to allowed devices")
        
        // Verify success message contains device information
        XCTAssertTrue(output.contains("Successfully bound device"), "Should show success message")
        XCTAssertTrue(output.contains(busid), "Should contain device busid")
        XCTAssertTrue(output.contains("05ac:030d"), "Should contain device VID:PID")
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
                default:
                    XCTFail("Expected deviceNotFound error, got: \(handlerError)")
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
        let targetDevice = devices.last! // Use Arduino device (20-1)
        let busid = "\(targetDevice.busID)-\(targetDevice.deviceID)"
        
        // Capture output
        let output = try captureStdout {
            try bindCommand.execute(with: [busid])
        }
        
        // Then: Only the target device should be bound
        let deviceIdentifier = "\(targetDevice.busID)-\(targetDevice.deviceID)"
        XCTAssertTrue(serverConfig.allowedDevices.contains(deviceIdentifier), 
                     "Target device should be bound")
        
        // Verify only one device is bound
        XCTAssertEqual(serverConfig.allowedDevices.count, 1, 
                      "Only one device should be bound")
        
        // Verify success message
        XCTAssertTrue(output.contains("Successfully bound device"), "Should show success message")
        XCTAssertTrue(output.contains("2341:0043"), "Should contain Arduino VID:PID")
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
        
        // Capture output
        let output = try captureStdout {
            try unbindCommand.execute(with: [busid])
        }
        
        // Then: Device should be removed from allowed devices
        XCTAssertFalse(serverConfig.allowedDevices.contains(busid), 
                      "Device should be removed from allowed devices")
        
        // Verify success message
        XCTAssertTrue(output.contains("Successfully unbound device"), "Should show success message")
        XCTAssertTrue(output.contains(busid), "Should contain device busid")
    }
    
    func testUnbindCommandWithNonboundDevice() throws {
        // Given: Device is not bound
        let unbindCommand = UnbindCommand(deviceDiscovery: mockDeviceDiscovery, serverConfig: serverConfig)
        
        // Verify device is not initially bound
        XCTAssertFalse(serverConfig.allowedDevices.contains("20-0"), 
                      "Device should not be initially bound")
        
        // Capture output
        let output = try captureStdout {
            try unbindCommand.execute(with: ["20-0"])
        }
        
        // Then: Should complete without error (graceful handling)
        XCTAssertTrue(output.contains("was not bound"), "Should indicate device was not bound")
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
    
    // MARK: - Helper Methods
    
    /// Capture stdout during block execution
    private func captureStdout<T>(_ block: () throws -> T) throws -> String {
        let originalStdout = dup(STDOUT_FILENO)
        let pipe = Pipe()
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        
        defer {
            fflush(stdout)
            dup2(originalStdout, STDOUT_FILENO)
            close(originalStdout)
            pipe.fileHandleForWriting.closeFile()
        }
        
        let _ = try block()
        
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        
        return output
    }
}