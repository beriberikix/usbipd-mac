// CommandHandlersTests.swift
// Tests for command handlers

import XCTest
import Foundation
@testable import USBIPDCLI
@testable import USBIPDCore
@testable import Common

// Test class for command handlers
class CommandHandlersTests: XCTestCase {
    
    var mockDeviceDiscovery: MockDeviceDiscovery!
    var mockServer: MockUSBIPServer!
    var serverConfig: ServerConfig!
    var mockOutputFormatter: MockOutputFormatter!
    
    override func setUp() {
        super.setUp()
        mockDeviceDiscovery = MockDeviceDiscovery()
        mockServer = MockUSBIPServer()
        serverConfig = ServerConfig()
        mockOutputFormatter = MockOutputFormatter()
        
        // Set up mock devices
        mockDeviceDiscovery.mockDevices = [
            USBDevice(
                busID: "1",
                deviceID: "2",
                vendorID: 0x1234,
                productID: 0x5678,
                deviceClass: 0x09,
                deviceSubClass: 0x00,
                deviceProtocol: 0x00,
                speed: .high,
                manufacturerString: "Mock Manufacturer",
                productString: "Mock Device",
                serialNumberString: "12345"
            ),
            USBDevice(
                busID: "1",
                deviceID: "3",
                vendorID: 0xABCD,
                productID: 0xEF01,
                deviceClass: 0x03,
                deviceSubClass: 0x01,
                deviceProtocol: 0x02,
                speed: .superSpeed,
                manufacturerString: "Another Manufacturer",
                productString: "Another Device",
                serialNumberString: "67890"
            )
        ]
    }
    
    override func tearDown() {
        mockDeviceDiscovery = nil
        mockServer = nil
        serverConfig = nil
        mockOutputFormatter = nil
        super.tearDown()
    }
    
    // MARK: - List Command Tests
    
    func testListCommand() throws {
        let listCommand = ListCommand(deviceDiscovery: mockDeviceDiscovery, outputFormatter: mockOutputFormatter)
        
        // Test successful execution
        try listCommand.execute(with: [])
        
        XCTAssertTrue(mockOutputFormatter.formatDeviceListCalled, "formatDeviceList should be called")
        XCTAssertEqual(mockOutputFormatter.lastDevices?.count, 2, "Should format 2 devices")
    }
    
    func testListCommandWithError() {
        let listCommand = ListCommand(deviceDiscovery: mockDeviceDiscovery, outputFormatter: mockOutputFormatter)
        
        // Set up to throw error
        mockDeviceDiscovery.shouldThrowError = true
        
        // Test error handling
        XCTAssertThrowsError(try listCommand.execute(with: [])) { error in
            XCTAssertTrue(error is CommandLineError, "Should throw CommandLineError")
        }
    }
    
    // MARK: - Bind Command Tests
    
    func testBindCommand() throws {
        let bindCommand = BindCommand(deviceDiscovery: mockDeviceDiscovery, serverConfig: serverConfig)
        
        // Test successful execution
        try bindCommand.execute(with: ["1-2"])
        
        // Check that device was added to allowed devices
        XCTAssertTrue(serverConfig.allowedDevices.contains("1-2"), "Device should be added to allowed devices")
    }
    
    func testBindCommandWithInvalidBusID() {
        let bindCommand = BindCommand(deviceDiscovery: mockDeviceDiscovery, serverConfig: serverConfig)
        
        // Test invalid busid format
        XCTAssertThrowsError(try bindCommand.execute(with: ["invalid"])) { error in
            XCTAssertTrue(error is CommandLineError, "Should throw CommandLineError")
        }
    }
    
    func testBindCommandWithNonexistentDevice() {
        let bindCommand = BindCommand(deviceDiscovery: mockDeviceDiscovery, serverConfig: serverConfig)
        
        // Test nonexistent device
        XCTAssertThrowsError(try bindCommand.execute(with: ["2-1"])) { error in
            XCTAssertTrue(error is CommandHandlerError, "Should throw CommandHandlerError")
        }
    }
    
    // MARK: - Unbind Command Tests
    
    func testUnbindCommand() throws {
        let unbindCommand = UnbindCommand(deviceDiscovery: mockDeviceDiscovery, serverConfig: serverConfig)
        
        // Add device to allowed devices first
        serverConfig.allowDevice("1-2")
        
        // Test successful execution
        try unbindCommand.execute(with: ["1-2"])
        
        // Check that device was removed from allowed devices
        XCTAssertFalse(serverConfig.allowedDevices.contains("1-2"), "Device should be removed from allowed devices")
    }
    
    func testUnbindCommandWithInvalidBusID() {
        let unbindCommand = UnbindCommand(deviceDiscovery: mockDeviceDiscovery, serverConfig: serverConfig)
        
        // Test invalid busid format
        XCTAssertThrowsError(try unbindCommand.execute(with: ["invalid"])) { error in
            XCTAssertTrue(error is CommandLineError, "Should throw CommandLineError")
        }
    }
    
    // MARK: - Daemon Command Tests
    
    func testDaemonCommand() throws {
        let daemonCommand = DaemonCommand(server: mockServer, serverConfig: serverConfig)
        
        // Test successful execution with foreground option
        // Note: We can't fully test the foreground mode as it enters a RunLoop
        // So we'll just check that the server is started
        try daemonCommand.execute(with: ["--foreground"])
        
        XCTAssertTrue(mockServer.isRunning(), "Server should be running")
    }
    
    func testDaemonCommandWithError() {
        let daemonCommand = DaemonCommand(server: mockServer, serverConfig: serverConfig)
        
        // Set up to throw error
        mockServer.shouldThrowError = true
        
        // Test error handling
        XCTAssertThrowsError(try daemonCommand.execute(with: [])) { error in
            XCTAssertTrue(error is CommandHandlerError, "Should throw CommandHandlerError")
        }
    }
    
    // MARK: - Attach and Detach Command Tests
    
    func testAttachCommand() {
        let attachCommand = AttachCommand()
        
        // Test that attach command throws not supported error
        XCTAssertThrowsError(try attachCommand.execute(with: ["localhost", "1-2"])) { error in
            XCTAssertTrue(error is CommandHandlerError, "Should throw CommandHandlerError")
            if let handlerError = error as? CommandHandlerError {
                switch handlerError {
                case .operationNotSupported:
                    // Expected error
                    break
                default:
                    XCTFail("Wrong error type: \(handlerError)")
                }
            }
        }
    }
    
    func testDetachCommand() {
        let detachCommand = DetachCommand()
        
        // Test that detach command throws not supported error
        XCTAssertThrowsError(try detachCommand.execute(with: ["1"])) { error in
            XCTAssertTrue(error is CommandHandlerError, "Should throw CommandHandlerError")
            if let handlerError = error as? CommandHandlerError {
                switch handlerError {
                case .operationNotSupported:
                    // Expected error
                    break
                default:
                    XCTFail("Wrong error type: \(handlerError)")
                }
            }
        }
    }
    
    // MARK: - Help Command Tests
    
    func testHelpCommand() throws {
        // Create a parser with our mock components
        let parser = CommandLineParser(
            deviceDiscovery: mockDeviceDiscovery,
            serverConfig: serverConfig,
            server: mockServer
        )
        
        // Get the help command from the parser
        let helpCommand = parser.getCommands().first { $0.name == "help" }
        XCTAssertNotNil(helpCommand, "Help command should exist")
        
        // Test execution (this just prints help, so we're just checking it doesn't throw)
        try helpCommand?.execute(with: [])
    }
    
    // MARK: - Output Formatter Tests
    
    func testDefaultOutputFormatter() {
        let formatter = DefaultOutputFormatter()
        let output = formatter.formatDeviceList(mockDeviceDiscovery.mockDevices)
        
        // Check that output contains expected strings
        XCTAssertTrue(output.contains("1-2"), "Output should contain device busid")
        XCTAssertTrue(output.contains("1234:5678"), "Output should contain device vendor/product IDs")
        XCTAssertTrue(output.contains("Mock Device"), "Output should contain device name")
    }
}