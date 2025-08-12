// AssertionHelpers.swift
// Shared assertion helpers and validation utilities for USB device validation, protocol message validation, and error checking
// This consolidates repeated assertion logic from existing tests

import XCTest
import Foundation
@testable import USBIPDCore
@testable import USBIPDCLI
@testable import Common

// MARK: - USB Device Validation Helpers

/// Assertion helpers for USB device validation
public struct USBDeviceAssertions {
    
    /// Assert that a USB device has valid basic properties
    public static func assertValidDevice(
        _ device: USBDevice,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(device.busID.isEmpty, "Bus ID should not be empty", file: file, line: line)
        XCTAssertFalse(device.deviceID.isEmpty, "Device ID should not be empty", file: file, line: line)
        XCTAssertTrue(device.vendorID >= 0, "Vendor ID should be valid", file: file, line: line)
        XCTAssertTrue(device.productID >= 0, "Product ID should be valid", file: file, line: line)
    }
    
    /// Assert that two USB devices are equal
    public static func assertDevicesEqual(
        _ device1: USBDevice,
        _ device2: USBDevice,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(device1.busID, device2.busID, "Bus IDs should match", file: file, line: line)
        XCTAssertEqual(device1.deviceID, device2.deviceID, "Device IDs should match", file: file, line: line)
        XCTAssertEqual(device1.vendorID, device2.vendorID, "Vendor IDs should match", file: file, line: line)
        XCTAssertEqual(device1.productID, device2.productID, "Product IDs should match", file: file, line: line)
        XCTAssertEqual(device1.deviceClass, device2.deviceClass, "Device classes should match", file: file, line: line)
        XCTAssertEqual(device1.deviceSubClass, device2.deviceSubClass, "Device subclasses should match", file: file, line: line)
        XCTAssertEqual(device1.deviceProtocol, device2.deviceProtocol, "Device protocols should match", file: file, line: line)
        XCTAssertEqual(device1.speed, device2.speed, "Device speeds should match", file: file, line: line)
        XCTAssertEqual(device1.manufacturerString, device2.manufacturerString, "Manufacturer strings should match", file: file, line: line)
        XCTAssertEqual(device1.productString, device2.productString, "Product strings should match", file: file, line: line)
        XCTAssertEqual(device1.serialNumberString, device2.serialNumberString, "Serial number strings should match", file: file, line: line)
    }
    
    /// Assert that a device collection contains expected devices
    public static func assertDeviceCollectionContains(
        _ devices: [USBDevice],
        expectedDevice: USBDevice,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let foundDevice = devices.first { device in
            device.busID == expectedDevice.busID && device.deviceID == expectedDevice.deviceID
        }
        XCTAssertNotNil(foundDevice, "Device collection should contain expected device", file: file, line: line)
        if let found = foundDevice {
            assertDevicesEqual(found, expectedDevice, file: file, line: line)
        }
    }
    
    /// Assert that a device has specific USB class properties
    public static func assertDeviceHasClass(
        _ device: USBDevice,
        deviceClass: UInt8,
        deviceSubClass: UInt8? = nil,
        deviceProtocol: UInt8? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(device.deviceClass, deviceClass, "Device class should match", file: file, line: line)
        if let subClass = deviceSubClass {
            XCTAssertEqual(device.deviceSubClass, subClass, "Device subclass should match", file: file, line: line)
        }
        if let deviceProtocolValue = deviceProtocol {
            XCTAssertEqual(device.deviceProtocol, deviceProtocolValue, "Device protocol should match", file: file, line: line)
        }
    }
    
    /// Assert that a device has expected speed
    public static func assertDeviceSpeed(
        _ device: USBDevice,
        expectedSpeed: USBSpeed,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(device.speed, expectedSpeed, "Device speed should match expected value", file: file, line: line)
    }
}

// MARK: - Protocol Message Validation Helpers

/// Assertion helpers for USB/IP protocol message validation
public struct ProtocolMessageAssertions {
    
    /// Assert that a USB/IP request has valid header properties
    public static func assertValidUSBIPRequest<T: USBIPRequest>(
        _ request: T,
        expectedVersion: UInt16 = 0x0111,
        expectedCommand: UInt16? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(request.version, expectedVersion, "Protocol version should match", file: file, line: line)
        if let command = expectedCommand {
            XCTAssertEqual(request.command, command, "Command should match expected value", file: file, line: line)
        }
        XCTAssertEqual(request.status, 0, "Status should be zero for requests", file: file, line: line)
    }
    
    /// Assert that a USB/IP response has valid header properties
    public static func assertValidUSBIPResponse<T: USBIPResponse>(
        _ response: T,
        expectedVersion: UInt16 = 0x0111,
        expectedCommand: UInt16? = nil,
        expectedStatus: UInt32 = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(response.version, expectedVersion, "Protocol version should match", file: file, line: line)
        if let command = expectedCommand {
            XCTAssertEqual(response.command, command, "Command should match expected value", file: file, line: line)
        }
        XCTAssertEqual(response.status, expectedStatus, "Status should match expected value", file: file, line: line)
    }
    
    /// Assert that a device description has valid properties
    public static func assertValidDeviceDescription(
        _ description: USBIPDeviceDescription,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(description.path.isEmpty, "Device path should not be empty", file: file, line: line)
        XCTAssertFalse(description.busid.isEmpty, "Bus ID should not be empty", file: file, line: line)
        XCTAssertTrue(description.busnum > 0, "Bus number should be positive", file: file, line: line)
        XCTAssertTrue(description.devnum > 0, "Device number should be positive", file: file, line: line)
        XCTAssertTrue(description.idVendor >= 0, "Vendor ID should be valid", file: file, line: line)
        XCTAssertTrue(description.idProduct >= 0, "Product ID should be valid", file: file, line: line)
    }
    
    /// Assert that message data encoding/decoding is consistent
    public static func assertMessageRoundTrip<T: Codable & Equatable>(
        _ message: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(message)
            
            let decoder = JSONDecoder()
            let decodedMessage = try decoder.decode(T.self, from: data)
            
            XCTAssertEqual(message, decodedMessage, "Message should survive encoding/decoding round trip", file: file, line: line)
        } catch {
            XCTFail("Message round trip failed: \(error)", file: file, line: line)
        }
    }
}

// MARK: - Error Validation Helpers

/// Assertion helpers for error checking and validation
public struct ErrorAssertions {
    
    /// Assert that a specific error type is thrown
    public static func assertThrowsError<T: Error>(
        _ errorType: T.Type,
        _ expression: @autoclosure () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) where T: Equatable {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertTrue(error is T, "Should throw \(errorType) but got \(type(of: error))", file: file, line: line)
        }
    }
    
    /// Assert that a DeviceDiscoveryError is thrown with specific type
    public static func assertThrowsDeviceDiscoveryError(
        _ expectedError: DeviceDiscoveryError,
        _ expression: @autoclosure () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            guard let discoveryError = error as? DeviceDiscoveryError else {
                XCTFail("Expected DeviceDiscoveryError but got \(type(of: error))", file: file, line: line)
                return
            }
            XCTAssertEqual(discoveryError, expectedError, "Should throw specific DeviceDiscoveryError", file: file, line: line)
        }
    }
    
    /// Assert that a ServerError is thrown with specific type
    public static func assertThrowsServerError(
        _ expectedErrorType: String,
        _ expression: @autoclosure () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            guard let serverError = error as? ServerError else {
                XCTFail("Expected ServerError but got \(type(of: error))", file: file, line: line)
                return
            }
            
            switch serverError {
            case .initializationFailed(let message):
                if expectedErrorType == "initializationFailed" {
                    XCTAssertTrue(true, "Correctly threw initializationFailed error", file: file, line: line)
                } else {
                    XCTFail("Expected \(expectedErrorType) but got initializationFailed: \(message)", file: file, line: line)
                }
            default:
                XCTFail("Unexpected ServerError type: \(serverError)", file: file, line: line)
            }
        }
    }
    
    /// Assert that no error is thrown
    public static func assertNoThrow(
        _ expression: @autoclosure () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNoThrow(try expression(), file: file, line: line)
    }
}

// MARK: - Server Configuration Validation Helpers

/// Assertion helpers for server configuration validation
public struct ServerConfigAssertions {
    
    /// Assert that a server configuration has valid properties
    public static func assertValidServerConfig(
        _ config: ServerConfig,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(config.port > 0 && config.port <= 65535, "Port should be in valid range", file: file, line: line)
        XCTAssertTrue(config.maxConnections > 0, "Max connections should be positive", file: file, line: line)
        XCTAssertTrue(config.connectionTimeout > 0, "Connection timeout should be positive", file: file, line: line)
    }
    
    /// Assert that server configuration validation succeeds
    public static func assertConfigValidationSucceeds(
        _ config: ServerConfig,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNoThrow(try config.validate(), "Server configuration should be valid", file: file, line: line)
    }
    
    /// Assert that server configuration validation fails
    public static func assertConfigValidationFails(
        _ config: ServerConfig,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try config.validate(), "Server configuration should be invalid", file: file, line: line)
    }
    
    /// Assert that two server configurations are equal
    public static func assertConfigsEqual(
        _ config1: ServerConfig,
        _ config2: ServerConfig,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(config1.port, config2.port, "Ports should match", file: file, line: line)
        XCTAssertEqual(config1.logLevel, config2.logLevel, "Log levels should match", file: file, line: line)
        XCTAssertEqual(config1.debugMode, config2.debugMode, "Debug modes should match", file: file, line: line)
        XCTAssertEqual(config1.maxConnections, config2.maxConnections, "Max connections should match", file: file, line: line)
        XCTAssertEqual(config1.connectionTimeout, config2.connectionTimeout, "Connection timeouts should match", file: file, line: line)
        XCTAssertEqual(config1.allowedDevices, config2.allowedDevices, "Allowed devices should match", file: file, line: line)
        XCTAssertEqual(config1.autoBindDevices, config2.autoBindDevices, "Auto bind devices should match", file: file, line: line)
        XCTAssertEqual(config1.logFilePath, config2.logFilePath, "Log file paths should match", file: file, line: line)
    }
}

// MARK: - System Extension Validation Helpers

/// Assertion helpers for System Extension validation
public struct SystemExtensionAssertions {
    
    /// Assert that a System Extension bundle has valid properties
    public static func assertValidBundleConfig(
        _ config: SystemExtensionBundleConfig,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(config.bundleIdentifier.isEmpty, "Bundle identifier should not be empty", file: file, line: line)
        XCTAssertFalse(config.bundleName.isEmpty, "Bundle name should not be empty", file: file, line: line)
        XCTAssertFalse(config.bundleVersion.isEmpty, "Bundle version should not be empty", file: file, line: line)
        XCTAssertFalse(config.buildVersion.isEmpty, "Build version should not be empty", file: file, line: line)
        XCTAssertFalse(config.teamIdentifier.isEmpty, "Team identifier should not be empty", file: file, line: line)
        XCTAssertFalse(config.codeSigningIdentity.isEmpty, "Code signing identity should not be empty", file: file, line: line)
        XCTAssertFalse(config.capabilities.isEmpty, "Capabilities should not be empty", file: file, line: line)
    }
    
    /// Assert that System Extension installation data is valid
    public static func assertValidInstallationData(
        _ data: SystemExtensionInstallationData,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(data.bundlePath.isEmpty, "Bundle path should not be empty", file: file, line: line)
        XCTAssertFalse(data.identifier.isEmpty, "Identifier should not be empty", file: file, line: line)
        XCTAssertFalse(data.teamIdentifier.isEmpty, "Team identifier should not be empty", file: file, line: line)
        XCTAssertFalse(data.codeSignature.isEmpty, "Code signature should not be empty", file: file, line: line)
    }
}

// MARK: - Test Execution Helpers

/// General test execution and timing helpers
public struct TestExecutionAssertions {
    
    /// Assert that an operation completes within a specified time limit
    public static func assertCompletesWithinTimeLimit(
        _ timeLimit: TimeInterval,
        _ operation: @escaping () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTestExpectation(description: "Operation should complete within time limit")
        let startTime = Date()
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try operation()
                let executionTime = Date().timeIntervalSince(startTime)
                if executionTime <= timeLimit {
                    expectation.fulfill()
                } else {
                    XCTFail("Operation took \(executionTime)s, expected <= \(timeLimit)s", file: file, line: line)
                }
            } catch {
                XCTFail("Operation failed with error: \(error)", file: file, line: line)
            }
        }
        
        let waiterResult = XCTWaiter().wait(for: [expectation], timeout: timeLimit + 1.0)
        XCTAssertEqual(waiterResult, .completed, "Operation should complete within time limit", file: file, line: line)
    }
    
    /// Assert that a collection has expected count
    public static func assertCollectionCount<T>(
        _ collection: [T],
        expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(collection.count, expectedCount, "Collection should have expected count", file: file, line: line)
    }
    
    /// Assert that a collection is not empty
    public static func assertCollectionNotEmpty<T>(
        _ collection: [T],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(collection.isEmpty, "Collection should not be empty", file: file, line: line)
    }
    
    /// Assert that a collection is empty
    public static func assertCollectionEmpty<T>(
        _ collection: [T],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(collection.isEmpty, "Collection should be empty", file: file, line: line)
    }
}