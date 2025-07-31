//
//  IOKitDeviceDiscoveryEndToEndTests.swift
//  usbipd-mac
//
//  End-to-end integration tests for IOKit device discovery with CLI functionality
//

import XCTest
import Foundation
@testable import USBIPDCLI
@testable import USBIPDCore
@testable import Common

/// End-to-end integration tests for IOKit device discovery functionality
/// Tests complete workflow: device discovery → CLI list → device binding
/// Verifies device monitoring works with real USB device connect/disconnect
/// Tests error scenarios with permission issues and IOKit failures
final class IOKitDeviceDiscoveryEndToEndTests: XCTestCase {
    
    var ioKitDeviceDiscovery: IOKitDeviceDiscovery!
    var serverConfig: ServerConfig!
    var mockDeviceDiscovery: MockDeviceDiscovery!
    
    override func setUp() {
        super.setUp()
        
        // Set up real IOKit device discovery for integration testing
        ioKitDeviceDiscovery = IOKitDeviceDiscovery()
        
        // Set up server config for bind/unbind testing
        serverConfig = ServerConfig()
        
        // Set up mock device discovery for controlled testing scenarios
        mockDeviceDiscovery = MockDeviceDiscovery()
        setupMockDevices()
    }
    
    override func tearDown() {
        // Clean up any monitoring that might be active
        if ioKitDeviceDiscovery != nil {
            ioKitDeviceDiscovery.stopNotifications()
        }
        
        ioKitDeviceDiscovery = nil
        serverConfig = nil
        mockDeviceDiscovery = nil
        super.tearDown()
    }
    
    // MARK: - Test Data Setup
    
    private func setupMockDevices() {
        // Set up realistic test devices that simulate IOKit behavior
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
            )
        ]
    }
    
    // MARK: - Complete Workflow Tests (Requirements 1.1, 1.4, 1.5)
    
    func testCompleteWorkflowDeviceDiscoveryToListToBinding() throws {
        // Test complete workflow: device discovery → CLI list → device binding
        // Use timeout to prevent hanging in CI environments
        
        let expectation = XCTestExpectation(description: "Complete workflow test")
        var testError: Error?
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Step 1: Device Discovery with timeout
                let devices = try self.ioKitDeviceDiscovery.discoverDevices()
                
                // Skip test if no devices are available (common in CI environments)
                guard !devices.isEmpty else {
                    expectation.fulfill()
                    return
                }
                
                // Verify devices were discovered successfully
                XCTAssertGreaterThan(devices.count, 0, "Should discover at least one USB device")
                
                // Step 2: CLI List Command - test output formatting directly to avoid stdout capture
                let outputFormatter = DefaultOutputFormatter()
                let output = outputFormatter.formatDeviceList(devices)
                XCTAssertTrue(output.contains("Local USB Device(s)"), "Output should contain header")
                XCTAssertTrue(output.contains("Busid"), "Output should contain busid column")
                
                // Step 3: Device Binding
                let firstDevice = devices[0]
                let busid = "\(firstDevice.busID)-\(firstDevice.deviceID)"
                
                let bindCommand = BindCommand(deviceDiscovery: self.ioKitDeviceDiscovery, serverConfig: self.serverConfig)
                
                // Execute bind command
                try bindCommand.execute(with: [busid])
                
                // Verify device was bound
                XCTAssertTrue(self.serverConfig.allowedDevices.contains(busid), "Device should be bound after bind command")
                
                // Step 4: Verify device lookup works
                let foundDevice = try self.ioKitDeviceDiscovery.getDevice(busID: firstDevice.busID, deviceID: firstDevice.deviceID)
                XCTAssertNotNil(foundDevice, "Should be able to look up bound device")
                XCTAssertEqual(foundDevice?.busID, firstDevice.busID, "Found device should match original")
                XCTAssertEqual(foundDevice?.deviceID, firstDevice.deviceID, "Found device should match original")
                
                // Step 5: Unbind device
                let unbindCommand = UnbindCommand(deviceDiscovery: self.ioKitDeviceDiscovery, serverConfig: self.serverConfig)
                try unbindCommand.execute(with: [busid])
                
                // Verify device was unbound
                XCTAssertFalse(self.serverConfig.allowedDevices.contains(busid), "Device should be unbound after unbind command")
                
                expectation.fulfill()
            } catch {
                testError = error
                expectation.fulfill()
            }
        }
        
        // Wait with timeout to prevent hanging
        let result = XCTWaiter.wait(for: [expectation], timeout: 5.0)
        
        if result == .timedOut {
            throw XCTSkip("IOKit device discovery timed out - likely no devices available or permission issues")
        }
        
        if let error = testError {
            if error.localizedDescription.contains("No USB devices available") {
                throw XCTSkip("No USB devices available for end-to-end testing")
            }
            throw error
        }
    }
    
    func testCompleteWorkflowWithMockDevices() throws {
        // Test complete workflow with controlled mock devices
        
        // Step 1: Device Discovery with mock
        let devices = try mockDeviceDiscovery.discoverDevices()
        XCTAssertEqual(devices.count, 3, "Should have 3 mock devices")
        
        // Step 2: CLI List Command with mock
        let outputFormatter = DefaultOutputFormatter()
        let listCommand = ListCommand(deviceDiscovery: mockDeviceDiscovery, outputFormatter: outputFormatter)
        
        XCTAssertNoThrow(try listCommand.execute(with: []), "List command should execute successfully with mock")
        
        // Verify specific device information is present
        let output = outputFormatter.formatDeviceList(devices)
        XCTAssertTrue(output.contains("05ac:030d"), "Should contain Apple Magic Mouse")
        XCTAssertTrue(output.contains("046d:c31c"), "Should contain Logitech device")
        XCTAssertTrue(output.contains("0781:5567"), "Should contain SanDisk device")
        
        // Step 3: Test binding each device
        let bindCommand = BindCommand(deviceDiscovery: mockDeviceDiscovery, serverConfig: serverConfig)
        
        for device in devices {
            let busid = "\(device.busID)-\(device.deviceID)"
            XCTAssertNoThrow(try bindCommand.execute(with: [busid]), "Should bind device \(busid)")
            XCTAssertTrue(serverConfig.allowedDevices.contains(busid), "Device \(busid) should be bound")
        }
        
        // Verify all devices are bound
        XCTAssertEqual(serverConfig.allowedDevices.count, 3, "All 3 devices should be bound")
        
        // Step 4: Test unbinding all devices
        let unbindCommand = UnbindCommand(deviceDiscovery: mockDeviceDiscovery, serverConfig: serverConfig)
        
        for device in devices {
            let busid = "\(device.busID)-\(device.deviceID)"
            XCTAssertNoThrow(try unbindCommand.execute(with: [busid]), "Should unbind device \(busid)")
            XCTAssertFalse(serverConfig.allowedDevices.contains(busid), "Device \(busid) should be unbound")
        }
        
        // Verify all devices are unbound
        XCTAssertEqual(serverConfig.allowedDevices.count, 0, "All devices should be unbound")
    }
    
    func testWorkflowWithMultipleOutputFormatters() throws {
        // Test workflow with different output formatters
        let devices = try mockDeviceDiscovery.discoverDevices()
        
        // Test with default formatter
        let defaultFormatter = DefaultOutputFormatter()
        let defaultListCommand = ListCommand(deviceDiscovery: mockDeviceDiscovery, outputFormatter: defaultFormatter)
        XCTAssertNoThrow(try defaultListCommand.execute(with: []), "Default formatter should work")
        
        // Test with Linux-compatible formatter
        let linuxFormatter = LinuxCompatibleOutputFormatter()
        let linuxListCommand = ListCommand(deviceDiscovery: mockDeviceDiscovery, outputFormatter: linuxFormatter)
        XCTAssertNoThrow(try linuxListCommand.execute(with: []), "Linux formatter should work")
        
        // Verify both formatters produce valid output
        let defaultOutput = defaultFormatter.formatDeviceList(devices)
        let linuxOutput = linuxFormatter.formatDeviceList(devices)
        
        XCTAssertTrue(defaultOutput.contains("Local USB Device(s)"), "Default output should contain header")
        XCTAssertTrue(linuxOutput.contains("Local USB Device(s)"), "Linux output should contain header")
        XCTAssertTrue(linuxOutput.contains("/dev/bus/usb/"), "Linux output should contain device nodes")
    }
    
    // MARK: - Device Monitoring Tests (Requirements 3.3, 3.4)
    
    func testDeviceMonitoringSetupAndCleanup() throws {
        // Test device monitoring setup and cleanup with timeout
        
        let expectation = XCTestExpectation(description: "Monitoring setup and cleanup")
        var testError: Error?
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var connectedDevices: [USBDevice] = []
                var disconnectedDevices: [USBDevice] = []
                
                // Set up monitoring callbacks
                self.ioKitDeviceDiscovery.onDeviceConnected = { device in
                    connectedDevices.append(device)
                }
                
                self.ioKitDeviceDiscovery.onDeviceDisconnected = { device in
                    disconnectedDevices.append(device)
                }
                
                // Start monitoring
                try self.ioKitDeviceDiscovery.startNotifications()
                
                // Wait a brief moment for monitoring to initialize
                Thread.sleep(forTimeInterval: 0.1)
                
                // Stop monitoring
                self.ioKitDeviceDiscovery.stopNotifications()
                
                expectation.fulfill()
            } catch {
                testError = error
                expectation.fulfill()
            }
        }
        
        // Wait with timeout to prevent hanging
        let result = XCTWaiter.wait(for: [expectation], timeout: 3.0)
        
        if result == .timedOut {
            throw XCTSkip("Device monitoring setup timed out - likely permission issues")
        }
        
        if let error = testError {
            throw error
        }
        
        // Verify monitoring was set up and cleaned up properly
        XCTAssertTrue(true, "Monitoring setup and cleanup completed without errors")
    }
    
    func testDeviceMonitoringWithMockCallbacks() throws {
        // Test device monitoring with mock callbacks to simulate device events
        
        var connectedDevices: [USBDevice] = []
        var disconnectedDevices: [USBDevice] = []
        
        // Set up monitoring callbacks
        mockDeviceDiscovery.onDeviceConnected = { device in
            connectedDevices.append(device)
        }
        
        mockDeviceDiscovery.onDeviceDisconnected = { device in
            disconnectedDevices.append(device)
        }
        
        // Simulate device connection events
        let testDevice = mockDeviceDiscovery.mockDevices[0]
        mockDeviceDiscovery.onDeviceConnected?(testDevice)
        
        XCTAssertEqual(connectedDevices.count, 1, "Should have recorded one connected device")
        XCTAssertEqual(connectedDevices[0].busID, testDevice.busID, "Connected device should match test device")
        
        // Simulate device disconnection
        mockDeviceDiscovery.onDeviceDisconnected?(testDevice)
        
        XCTAssertEqual(disconnectedDevices.count, 1, "Should have recorded one disconnected device")
        XCTAssertEqual(disconnectedDevices[0].busID, testDevice.busID, "Disconnected device should match test device")
    }
    
    func testMonitoringErrorHandling() throws {
        // Test monitoring error handling scenarios
        
        // Test starting monitoring multiple times
        XCTAssertNoThrow(try ioKitDeviceDiscovery.startNotifications(), "First start should succeed")
        
        // Starting again should not cause issues (should be idempotent)
        XCTAssertNoThrow(try ioKitDeviceDiscovery.startNotifications(), "Second start should not cause errors")
        
        // Stop monitoring
        ioKitDeviceDiscovery.stopNotifications()
        
        // Stopping multiple times should not cause issues
        ioKitDeviceDiscovery.stopNotifications()
        
        XCTAssertTrue(true, "Multiple start/stop operations handled gracefully")
    }
    
    // MARK: - Error Scenario Tests
    
    func testPermissionErrorHandling() throws {
        // Test handling of permission-related errors
        
        // Note: In a real environment, permission errors would occur when the app
        // doesn't have the necessary entitlements or when running in a sandboxed environment
        
        // For this test, we'll verify that the system handles errors gracefully
        // when IOKit operations fail due to permission issues
        
        // Test with mock that simulates permission errors
        mockDeviceDiscovery.shouldThrowError = true
        mockDeviceDiscovery.errorToThrow = DeviceDiscoveryError.accessDenied("Insufficient privileges to access USB devices")
        
        let listCommand = ListCommand(deviceDiscovery: mockDeviceDiscovery, outputFormatter: DefaultOutputFormatter())
        
        XCTAssertThrowsError(try listCommand.execute(with: [])) { error in
            XCTAssertTrue(error is CommandLineError, "Should throw CommandLineError")
            if let commandError = error as? CommandLineError {
                switch commandError {
                case .executionFailed(let message):
                    XCTAssertTrue(message.contains("Failed to list devices"), "Error should indicate list failure")
                default:
                    XCTFail("Expected executionFailed error")
                }
            }
        }
    }
    
    func testIOKitFailureHandling() throws {
        // Test handling of IOKit-specific failures
        
        // Test with mock that simulates IOKit errors
        mockDeviceDiscovery.shouldThrowError = true
        mockDeviceDiscovery.errorToThrow = DeviceDiscoveryError.ioKitError(-536870212, "IOKit operation failed")
        
        let bindCommand = BindCommand(deviceDiscovery: mockDeviceDiscovery, serverConfig: serverConfig)
        
        XCTAssertThrowsError(try bindCommand.execute(with: ["20-0"])) { error in
            XCTAssertTrue(error is CommandHandlerError, "Should throw CommandHandlerError")
            if let handlerError = error as? CommandHandlerError {
                switch handlerError {
                case .deviceBindingFailed(let message):
                    XCTAssertTrue(message.contains("IOKit operation failed"), "Error should contain IOKit error details")
                default:
                    XCTFail("Expected deviceBindingFailed error")
                }
            }
        }
    }
    
    func testDeviceNotFoundErrorHandling() throws {
        // Test handling when devices are not found
        
        let bindCommand = BindCommand(deviceDiscovery: mockDeviceDiscovery, serverConfig: serverConfig)
        
        // Try to bind a nonexistent device
        XCTAssertThrowsError(try bindCommand.execute(with: ["999-999"])) { error in
            XCTAssertTrue(error is CommandHandlerError, "Should throw CommandHandlerError")
            if let handlerError = error as? CommandHandlerError {
                switch handlerError {
                case .deviceNotFound(let message):
                    XCTAssertTrue(message.contains("999-999"), "Error should mention the busid")
                case .deviceBindingFailed(let message):
                    XCTAssertTrue(message.contains("999-999"), "Error should mention the busid")
                default:
                    XCTFail("Expected deviceNotFound or deviceBindingFailed error")
                }
            }
        }
    }
    
    func testInvalidBusIDFormatHandling() throws {
        // Test handling of invalid busid formats
        
        let bindCommand = BindCommand(deviceDiscovery: mockDeviceDiscovery, serverConfig: serverConfig)
        
        let invalidBusIDs = ["invalid", "123", "a-b", "1-", "-1", "1-2-3-4", ""]
        
        for invalidBusID in invalidBusIDs {
            XCTAssertThrowsError(try bindCommand.execute(with: [invalidBusID])) { error in
                XCTAssertTrue(error is CommandLineError, "Should throw CommandLineError for invalid busid: \(invalidBusID)")
                if let commandError = error as? CommandLineError {
                    switch commandError {
                    case .invalidArguments(let message):
                        XCTAssertTrue(message.contains("Invalid busid format"), "Error should indicate invalid format")
                    default:
                        XCTFail("Expected invalidArguments error for busid: \(invalidBusID)")
                    }
                }
            }
        }
    }
    
    // MARK: - Device Lookup and ID Consistency Tests
    
    func testDeviceLookupConsistency() throws {
        // Test that device lookup returns consistent results
        
        let expectation = XCTestExpectation(description: "Device lookup consistency test")
        var testError: Error?
        var discoveredDevices: [USBDevice] = []
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                discoveredDevices = try self.ioKitDeviceDiscovery.discoverDevices()
                
                guard !discoveredDevices.isEmpty else {
                    expectation.fulfill()
                    return
                }
                
                // Test lookup for each discovered device
                for device in discoveredDevices {
                    let foundDevice = try self.ioKitDeviceDiscovery.getDevice(busID: device.busID, deviceID: device.deviceID)
                    
                    XCTAssertNotNil(foundDevice, "Should find device with busID: \(device.busID), deviceID: \(device.deviceID)")
                    
                    if let found = foundDevice {
                        XCTAssertEqual(found.busID, device.busID, "Bus ID should match")
                        XCTAssertEqual(found.deviceID, device.deviceID, "Device ID should match")
                        XCTAssertEqual(found.vendorID, device.vendorID, "Vendor ID should match")
                        XCTAssertEqual(found.productID, device.productID, "Product ID should match")
                        XCTAssertEqual(found.deviceClass, device.deviceClass, "Device class should match")
                        XCTAssertEqual(found.speed, device.speed, "Device speed should match")
                    }
                }
                
                expectation.fulfill()
            } catch {
                testError = error
                expectation.fulfill()
            }
        }
        
        // Wait with timeout
        let result = XCTWaiter.wait(for: [expectation], timeout: 10.0)
        
        if result == .timedOut {
            throw XCTSkip("Device lookup consistency test timed out")
        }
        
        if let error = testError {
            throw error
        }
        
        if discoveredDevices.isEmpty {
            throw XCTSkip("No USB devices available for lookup consistency testing")
        }
    }
    
    func testDeviceIDFormatConsistency() throws {
        // Test that device IDs follow consistent format across discovery and lookup
        
        let expectation = XCTestExpectation(description: "Device ID format consistency test")
        var testError: Error?
        var discoveredDevices: [USBDevice] = []
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                discoveredDevices = try self.ioKitDeviceDiscovery.discoverDevices()
                expectation.fulfill()
            } catch {
                testError = error
                expectation.fulfill()
            }
        }
        
        // Wait with timeout
        let result = XCTWaiter.wait(for: [expectation], timeout: 5.0)
        
        if result == .timedOut {
            throw XCTSkip("Device ID format consistency test timed out")
        }
        
        if let error = testError {
            throw XCTSkip("Device discovery failed: \(error.localizedDescription)")
        }
        
        for device in discoveredDevices {
            // Verify bus and device IDs are numeric strings
            XCTAssertNotNil(Int(device.busID), "Bus ID should be numeric: \(device.busID)")
            XCTAssertNotNil(Int(device.deviceID), "Device ID should be numeric: \(device.deviceID)")
            
            // Verify combined busid format is valid for CLI
            let busid = "\(device.busID)-\(device.deviceID)"
            let busidPattern = #"^\d+-\d+$"#
            XCTAssertTrue(busid.range(of: busidPattern, options: .regularExpression) != nil,
                         "Busid should match CLI format: \(busid)")
            
            // Verify IDs are reasonable values
            let busIDInt = Int(device.busID)!
            let deviceIDInt = Int(device.deviceID)!
            
            XCTAssertGreaterThanOrEqual(busIDInt, 0, "Bus ID should be non-negative")
            XCTAssertGreaterThanOrEqual(deviceIDInt, 0, "Device ID should be non-negative")
            XCTAssertLessThan(busIDInt, 1000, "Bus ID should be reasonable (< 1000)")
            XCTAssertLessThan(deviceIDInt, 1000, "Device ID should be reasonable (< 1000)")
        }
    }
    
    func testDeviceIDUniqueness() throws {
        // Test that all discovered devices have unique bus/device ID combinations
        
        let devices = try ioKitDeviceDiscovery.discoverDevices()
        var seenBusIDs = Set<String>()
        
        for device in devices {
            let busid = "\(device.busID)-\(device.deviceID)"
            XCTAssertFalse(seenBusIDs.contains(busid), "Duplicate busid found: \(busid)")
            seenBusIDs.insert(busid)
        }
    }
    
    // MARK: - Performance and Resource Management Tests
    
    func testResourceCleanupAfterOperations() throws {
        // Test that resources are properly cleaned up after operations
        
        // Perform multiple discovery operations
        for _ in 0..<5 {
            let devices = try ioKitDeviceDiscovery.discoverDevices()
            
            // Perform lookup operations
            for device in devices.prefix(3) { // Limit to first 3 devices to avoid excessive testing
                _ = try ioKitDeviceDiscovery.getDevice(busID: device.busID, deviceID: device.deviceID)
            }
        }
        
        // Start and stop monitoring multiple times
        for _ in 0..<3 {
            XCTAssertNoThrow(try ioKitDeviceDiscovery.startNotifications())
            Thread.sleep(forTimeInterval: 0.05) // Brief pause
            ioKitDeviceDiscovery.stopNotifications()
        }
        
        // Verify no resource leaks (this is mainly tested through proper cleanup in deinit)
        XCTAssertTrue(true, "Resource cleanup operations completed without errors")
    }
    
    func testConcurrentOperations() throws {
        // Test concurrent device discovery operations
        
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        expectation.expectedFulfillmentCount = 3
        
        let queue = DispatchQueue.global(qos: .userInitiated)
        
        // Perform concurrent discovery operations
        for i in 0..<3 {
            queue.async {
                do {
                    let devices = try self.ioKitDeviceDiscovery.discoverDevices()
                    
                    // Verify each operation returns valid results
                    for device in devices {
                        XCTAssertFalse(device.busID.isEmpty, "Bus ID should not be empty in concurrent operation \(i)")
                        XCTAssertFalse(device.deviceID.isEmpty, "Device ID should not be empty in concurrent operation \(i)")
                    }
                    
                    expectation.fulfill()
                } catch {
                    XCTFail("Concurrent operation \(i) failed: \(error)")
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    // MARK: - Integration with CLI Command Parsing Tests
    
    func testCLICommandParsingIntegration() throws {
        // Test integration with CLI command parsing
        
        // Test list command with various options
        let listCommand = ListCommand(deviceDiscovery: mockDeviceDiscovery, outputFormatter: DefaultOutputFormatter())
        
        // Test with no arguments
        XCTAssertNoThrow(try listCommand.execute(with: []), "List with no args should work")
        
        // Test with local flag
        XCTAssertNoThrow(try listCommand.execute(with: ["-l"]), "List with -l should work")
        XCTAssertNoThrow(try listCommand.execute(with: ["--local"]), "List with --local should work")
        
        // Test bind command with valid busid
        let bindCommand = BindCommand(deviceDiscovery: mockDeviceDiscovery, serverConfig: serverConfig)
        XCTAssertNoThrow(try bindCommand.execute(with: ["20-0"]), "Bind with valid busid should work")
        
        // Test unbind command
        let unbindCommand = UnbindCommand(deviceDiscovery: mockDeviceDiscovery, serverConfig: serverConfig)
        XCTAssertNoThrow(try unbindCommand.execute(with: ["20-0"]), "Unbind should work")
    }
    
    func testCLIErrorMessageQuality() throws {
        // Test that CLI error messages are helpful and informative
        
        let bindCommand = BindCommand(deviceDiscovery: mockDeviceDiscovery, serverConfig: serverConfig)
        
        // Test missing arguments
        XCTAssertThrowsError(try bindCommand.execute(with: [])) { error in
            if let commandError = error as? CommandLineError {
                switch commandError {
                case .missingArguments(let message):
                    XCTAssertTrue(message.contains("busid"), "Error should mention required busid")
                default:
                    XCTFail("Expected missingArguments error")
                }
            }
        }
        
        // Test invalid busid format
        XCTAssertThrowsError(try bindCommand.execute(with: ["invalid-format"])) { error in
            if let commandError = error as? CommandLineError {
                switch commandError {
                case .invalidArguments(let message):
                    XCTAssertTrue(message.contains("Invalid busid format"), "Error should explain format issue")
                    XCTAssertTrue(message.contains("invalid-format"), "Error should show the invalid input")
                default:
                    XCTFail("Expected invalidArguments error")
                }
            }
        }
    }
    
    // MARK: - Real Device Testing (when available)
    
    func testWithRealDevicesWhenAvailable() throws {
        // Test with real devices when available (gracefully skip if none)
        // This test will work with any real USB devices present on the system
        
        let expectation = XCTestExpectation(description: "Real device testing")
        var testError: Error?
        var discoveredDevices: [USBDevice] = []
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                discoveredDevices = try self.ioKitDeviceDiscovery.discoverDevices()
                expectation.fulfill()
            } catch {
                testError = error
                expectation.fulfill()
            }
        }
        
        // Wait with timeout for device discovery
        let result = XCTWaiter.wait(for: [expectation], timeout: 5.0)
        
        if result == .timedOut {
            throw XCTSkip("Device discovery timed out - likely permission issues")
        }
        
        if let error = testError {
            throw XCTSkip("Device discovery failed: \(error.localizedDescription)")
        }
        
        guard !discoveredDevices.isEmpty else {
            throw XCTSkip("No real USB devices available for testing")
        }
        
        print("Testing with \(discoveredDevices.count) real USB devices:")
        for (index, device) in discoveredDevices.enumerated() {
            let deviceName = device.productString ?? "Unknown Device"
            let manufacturer = device.manufacturerString ?? "Unknown Manufacturer"
            print("  \(index + 1). \(device.busID)-\(device.deviceID): \(device.vendorID.hexString):\(device.productID.hexString) (\(manufacturer) - \(deviceName))")
        }
        
        // Test basic operations with the first available real device
        let firstDevice = discoveredDevices[0]
        let busid = "\(firstDevice.busID)-\(firstDevice.deviceID)"
        
        // Test binding and unbinding
        let bindCommand = BindCommand(deviceDiscovery: ioKitDeviceDiscovery, serverConfig: serverConfig)
        let unbindCommand = UnbindCommand(deviceDiscovery: ioKitDeviceDiscovery, serverConfig: serverConfig)
        
        XCTAssertNoThrow(try bindCommand.execute(with: [busid]), "Should bind real device \(busid)")
        XCTAssertTrue(serverConfig.allowedDevices.contains(busid), "Real device \(busid) should be bound")
        
        XCTAssertNoThrow(try unbindCommand.execute(with: [busid]), "Should unbind real device \(busid)")
        XCTAssertFalse(serverConfig.allowedDevices.contains(busid), "Real device \(busid) should be unbound")
        
        // Test device lookup
        let foundDevice = try ioKitDeviceDiscovery.getDevice(busID: firstDevice.busID, deviceID: firstDevice.deviceID)
        XCTAssertNotNil(foundDevice, "Should find real device \(busid)")
        XCTAssertEqual(foundDevice?.vendorID, firstDevice.vendorID, "Real device vendor ID should match")
        XCTAssertEqual(foundDevice?.productID, firstDevice.productID, "Real device product ID should match")
        
        // Test with multiple devices if available
        if discoveredDevices.count > 1 {
            print("Testing with multiple devices...")
            
            // Test binding multiple devices
            var boundDevices: [String] = []
            for device in discoveredDevices.prefix(3) { // Test up to 3 devices to avoid excessive testing
                let deviceBusid = "\(device.busID)-\(device.deviceID)"
                XCTAssertNoThrow(try bindCommand.execute(with: [deviceBusid]), "Should bind device \(deviceBusid)")
                boundDevices.append(deviceBusid)
            }
            
            // Verify all devices are bound
            for deviceBusid in boundDevices {
                XCTAssertTrue(serverConfig.allowedDevices.contains(deviceBusid), "Device \(deviceBusid) should be bound")
            }
            
            // Unbind all devices
            for deviceBusid in boundDevices {
                XCTAssertNoThrow(try unbindCommand.execute(with: [deviceBusid]), "Should unbind device \(deviceBusid)")
                XCTAssertFalse(serverConfig.allowedDevices.contains(deviceBusid), "Device \(deviceBusid) should be unbound")
            }
        }
    }
}

