// TestUtilities.swift
// Shared test utilities and mock classes for USBIPDCLI tests

import Foundation
@testable import USBIPDCLI
@testable import USBIPDCore
@testable import Common

// Mock device discovery for testing
class MockDeviceDiscovery: DeviceDiscovery {
    var onDeviceConnected: ((USBDevice) -> Void)?
    var onDeviceDisconnected: ((USBDevice) -> Void)?
    
    var mockDevices: [USBDevice] = []
    var shouldThrowError = false
    
    func discoverDevices() throws -> [USBDevice] {
        if shouldThrowError {
            throw DeviceDiscoveryError.failedToCreateMatchingDictionary
        }
        return mockDevices
    }
    
    func getDevice(busID: String, deviceID: String) throws -> USBDevice? {
        if shouldThrowError {
            throw DeviceDiscoveryError.failedToCreateMatchingDictionary
        }
        return mockDevices.first { $0.busID == busID && $0.deviceID == deviceID }
    }
    
    func startNotifications() throws {
        if shouldThrowError {
            throw DeviceDiscoveryError.failedToCreateNotificationPort
        }
    }
    
    func stopNotifications() {
        // No-op for mock
    }
}

// Mock server for testing
class MockUSBIPServer: USBIPServer {
    var onError: ((Error) -> Void)?
    var isServerRunning = false
    var shouldThrowError = false
    
    func start() throws {
        if shouldThrowError {
            throw ServerError.initializationFailed("Mock server start error")
        }
        isServerRunning = true
    }
    
    func stop() throws {
        if shouldThrowError {
            throw ServerError.initializationFailed("Mock server stop error")
        }
        isServerRunning = false
    }
    
    func isRunning() -> Bool {
        return isServerRunning
    }
}

// Mock output formatter for testing
class MockOutputFormatter: OutputFormatter {
    var formatDeviceListCalled = false
    var lastDevices: [USBDevice]?
    
    func formatDeviceList(_ devices: [USBDevice]) -> String {
        formatDeviceListCalled = true
        lastDevices = devices
        return "Mock formatted device list"
    }
    
    func formatDevice(_ device: USBDevice, detailed: Bool) -> String {
        return "Mock formatted device"
    }
    
    func formatError(_ error: Error) -> String {
        return "Mock error: \(error.localizedDescription)"
    }
    
    func formatSuccess(_ message: String) -> String {
        return "Mock success: \(message)"
    }
}