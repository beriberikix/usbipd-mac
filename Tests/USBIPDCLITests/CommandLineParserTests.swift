// CommandLineParserTests.swift
// Tests for the CommandLineParser class

import XCTest
@testable import USBIPDCLI
@testable import USBIPDCore
@testable import Common

final class CommandLineParserTests: XCTestCase {
    
    var parser: CommandLineParser!
    var mockDeviceDiscovery: MockDeviceDiscovery!
    var mockServerConfig: ServerConfig!
    var mockServer: MockUSBIPServer!
    
    override func setUp() {
        super.setUp()
        mockDeviceDiscovery = MockDeviceDiscovery()
        mockServerConfig = ServerConfig()
        mockServer = MockUSBIPServer()
        parser = CommandLineParser(deviceDiscovery: mockDeviceDiscovery, serverConfig: mockServerConfig, server: mockServer)
    }
    
    override func tearDown() {
        parser = nil
        mockDeviceDiscovery = nil
        mockServerConfig = nil
        mockServer = nil
        super.tearDown()
    }
    
    func testParserInitialization() {
        XCTAssertNotNil(parser)
        
        // Verify that commands are registered
        let commands = parser.getCommands()
        XCTAssertFalse(commands.isEmpty)
        
        // Check for required commands
        let commandNames = commands.map { $0.name }
        XCTAssertTrue(commandNames.contains("help"))
        XCTAssertTrue(commandNames.contains("list"))
        XCTAssertTrue(commandNames.contains("bind"))
        XCTAssertTrue(commandNames.contains("unbind"))
        XCTAssertTrue(commandNames.contains("attach"))
        XCTAssertTrue(commandNames.contains("detach"))
        XCTAssertTrue(commandNames.contains("daemon"))
    }
    
    func testUnknownCommand() {
        XCTAssertThrowsError(try parser.parse(arguments: ["program", "unknown"])) { error in
            guard let commandError = error as? CommandLineError else {
                XCTFail("Expected CommandLineError")
                return
            }
            
            if case .unknownCommand(let cmd) = commandError {
                XCTAssertEqual(cmd, "unknown")
            } else {
                XCTFail("Expected unknownCommand error")
            }
        }
    }
    
    func testMissingArguments() {
        XCTAssertThrowsError(try parser.parse(arguments: ["program", "bind"])) { error in
            guard let commandError = error as? CommandLineError else {
                XCTFail("Expected CommandLineError")
                return
            }
            
            if case .missingArguments = commandError {
                // Expected error
            } else {
                XCTFail("Expected missingArguments error")
            }
        }
    }
    
    func testInvalidArguments() {
        XCTAssertThrowsError(try parser.parse(arguments: ["program", "bind", "invalid-busid"])) { error in
            guard let commandError = error as? CommandLineError else {
                XCTFail("Expected CommandLineError")
                return
            }
            
            if case .invalidArguments = commandError {
                // Expected error
            } else {
                XCTFail("Expected invalidArguments error")
            }
        }
    }
}

// End of tests