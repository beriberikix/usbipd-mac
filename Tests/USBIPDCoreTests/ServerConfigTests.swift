// ServerConfigTests.swift
// Tests for ServerConfig class

import XCTest
import Foundation
import Common
@testable import USBIPDCore

final class ServerConfigTests: XCTestCase {
    
    // Temporary directory for test files
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        // Create a temporary directory for test files
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
    }
    
    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testDefaultInitialization() {
        let config = ServerConfig()
        
        XCTAssertEqual(config.port, ServerConfig.defaultPort)
        XCTAssertEqual(config.logLevel, ServerConfig.defaultLogLevel)
        XCTAssertFalse(config.debugMode)
        XCTAssertEqual(config.maxConnections, 10)
        XCTAssertEqual(config.connectionTimeout, 30.0)
        XCTAssertNil(config.logFilePath)
    }
    
    func testCustomInitialization() {
        let config = ServerConfig(
            port: 3241,
            logLevel: .debug,
            debugMode: true,
            maxConnections: 5,
            connectionTimeout: 60.0,
            logFilePath: "/tmp/usbipd.log"
        )
        
        XCTAssertEqual(config.port, 3241)
        XCTAssertEqual(config.logLevel, .debug)
        XCTAssertTrue(config.debugMode)
        XCTAssertEqual(config.maxConnections, 5)
        XCTAssertEqual(config.connectionTimeout, 60.0)
        XCTAssertEqual(config.logFilePath, "/tmp/usbipd.log")
    }
    
    func testSaveAndLoad() throws {
        let configPath = tempDir.appendingPathComponent("test-config.json").path
        
        // Create a custom config
        let originalConfig = ServerConfig(
            port: 3245,
            logLevel: .debug,
            debugMode: true,
            maxConnections: 15,
            connectionTimeout: 45.0,
            logFilePath: "/tmp/test-log.log"
        )
        
        // Save the config
        try originalConfig.save(to: configPath)
        
        // Load the config
        let loadedConfig = try ServerConfig.load(from: configPath)
        
        // Verify all properties match
        XCTAssertEqual(loadedConfig.port, originalConfig.port)
        XCTAssertEqual(loadedConfig.logLevel, originalConfig.logLevel)
        XCTAssertEqual(loadedConfig.debugMode, originalConfig.debugMode)
        XCTAssertEqual(loadedConfig.maxConnections, originalConfig.maxConnections)
        XCTAssertEqual(loadedConfig.connectionTimeout, originalConfig.connectionTimeout)
        XCTAssertEqual(loadedConfig.logFilePath, originalConfig.logFilePath)
    }
    
    func testLoadNonExistentFile() throws {
        let configPath = tempDir.appendingPathComponent("non-existent-config.json").path
        
        // Load should return default config when file doesn't exist
        let config = try ServerConfig.load(from: configPath)
        
        XCTAssertEqual(config.port, ServerConfig.defaultPort)
        XCTAssertEqual(config.logLevel, ServerConfig.defaultLogLevel)
    }
    
    func testValidation() {
        // Test invalid port
        var config = ServerConfig(port: 0)
        XCTAssertThrowsError(try config.validate()) { error in
            guard case ServerError.initializationFailed(_) = error else {
                XCTFail("Expected ServerError.initializationFailed")
                return
            }
        }
        
        // Test invalid max connections
        config = ServerConfig(maxConnections: 0)
        XCTAssertThrowsError(try config.validate()) { error in
            guard case ServerError.initializationFailed(_) = error else {
                XCTFail("Expected ServerError.initializationFailed")
                return
            }
        }
        
        // Test invalid connection timeout
        config = ServerConfig(connectionTimeout: 0)
        XCTAssertThrowsError(try config.validate()) { error in
            guard case ServerError.initializationFailed(_) = error else {
                XCTFail("Expected ServerError.initializationFailed")
                return
            }
        }
        
        // Test valid config
        config = ServerConfig()
        XCTAssertNoThrow(try config.validate())
    }
    
    // testDeviceAllowance moved to BoundDeviceStoreTests: the bind list is no longer
    // part of the configuration.

    func testShouldLog() {
        let config = ServerConfig(logLevel: .info)
        
        // Test log levels
        XCTAssertTrue(config.shouldLog(level: .error))   // error < info
        XCTAssertTrue(config.shouldLog(level: .warning)) // warning < info
        XCTAssertTrue(config.shouldLog(level: .info))    // info == info
        XCTAssertFalse(config.shouldLog(level: .debug))  // debug > info
    }
    
    func testLogLevelComparison() {
        // Test that log levels can be compared (debug is lowest, critical is highest)
        XCTAssertLessThan(LogLevel.debug, LogLevel.info)
        XCTAssertLessThan(LogLevel.info, LogLevel.warning)
        XCTAssertLessThan(LogLevel.warning, LogLevel.error)
        XCTAssertLessThan(LogLevel.error, LogLevel.critical)
    }
}