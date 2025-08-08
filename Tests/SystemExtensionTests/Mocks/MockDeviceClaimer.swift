// MockDeviceClaimer.swift
// Mock implementation of DeviceClaimer for isolated unit testing

import Foundation
import IOKit
import IOKit.usb
import Common
import USBIPDCore
@testable import SystemExtension

// MARK: - Mock Device Claimer

/// Mock implementation of DeviceClaimer protocol for testing System Extension logic
/// without requiring privileged access to actual USB devices
public class MockDeviceClaimer: DeviceClaimer {
    
    // MARK: - Mock Configuration
    
    /// Configuration for mock behaviors and test scenarios
    public struct MockConfiguration {
        /// Whether device claiming should succeed by default
        public var shouldSucceedClaiming = true
        
        /// Whether device releasing should succeed by default
        public var shouldSucceedReleasing = true
        
        /// Whether state restoration should succeed
        public var shouldSucceedRestoration = true
        
        /// Whether state saving should succeed
        public var shouldSucceedSaving = true
        
        /// Error to throw for claim operations (if shouldSucceedClaiming is false)
        public var claimError: SystemExtensionError = .deviceClaimFailed("test-device", nil)
        
        /// Error to throw for release operations (if shouldSucceedReleasing is false)
        public var releaseError: SystemExtensionError = .deviceReleaseFailed("test-device", nil)
        
        /// Error to throw for restoration operations (if shouldSucceedRestoration is false)
        public var restorationError: SystemExtensionError = .configurationError("Mock restoration failure")
        
        /// Error to throw for save operations (if shouldSucceedSaving is false)
        public var saveError: SystemExtensionError = .configurationError("Mock save failure")
        
        /// Delay to simulate device claiming operations (in seconds)
        public var claimDelay: TimeInterval = 0.0
        
        /// Delay to simulate device releasing operations (in seconds)
        public var releaseDelay: TimeInterval = 0.0
        
        /// Devices that should be restored from persistent state
        public var restoredDevices: [ClaimedDevice] = []
        
        /// Initial claimed devices (for testing scenarios where devices are pre-claimed)
        public var initialClaimedDevices: [ClaimedDevice] = []
        
        public init() {}
    }
    
    // MARK: - Mock State
    
    /// Current configuration for mock behavior
    public var configuration = MockConfiguration()
    
    /// Currently claimed devices (deviceID -> ClaimedDevice)
    private var claimedDevices: [String: ClaimedDevice] = [:]
    
    /// Track method calls for test verification
    public var methodCalls: [String] = []
    
    /// Track claimed device operations for verification
    public var claimOperations: [(device: USBDevice, timestamp: Date)] = []
    public var releaseOperations: [(deviceID: String, timestamp: Date)] = []
    
    /// Track state operations
    public var restoreOperations: [Date] = []
    public var saveOperations: [Date] = []
    
    /// Statistics for mock operations
    public var claimAttempts = 0
    public var successfulClaims = 0
    public var failedClaims = 0
    public var releaseAttempts = 0
    public var successfulReleases = 0
    public var failedReleases = 0
    
    // MARK: - Initialization
    
    public init() {
        // Pre-populate with initial claimed devices if configured
        resetToConfiguration()
    }
    
    public init(configuration: MockConfiguration) {
        self.configuration = configuration
        resetToConfiguration()
    }
    
    // MARK: - DeviceClaimer Protocol Implementation
    
    public func claimDevice(device: USBDevice) throws -> ClaimedDevice {
        methodCalls.append("claimDevice(\(device.busID)-\(device.deviceID))")
        claimAttempts += 1
        
        let deviceID = "\(device.busID)-\(device.deviceID)"
        
        // Simulate processing delay if configured
        if configuration.claimDelay > 0 {
            Thread.sleep(forTimeInterval: configuration.claimDelay)
        }
        
        // Check if claiming should fail
        if !configuration.shouldSucceedClaiming {
            failedClaims += 1
            throw configuration.claimError
        }
        
        // Check if device is already claimed
        if claimedDevices[deviceID] != nil {
            failedClaims += 1
            throw SystemExtensionError.deviceAlreadyClaimed(deviceID)
        }
        
        // Create claimed device with mock data
        let claimedDevice = ClaimedDevice(
            deviceID: deviceID,
            busID: device.busID,
            vendorID: device.vendorID,
            productID: device.productID,
            productString: device.productString,
            manufacturerString: device.manufacturerString,
            serialNumber: device.serialNumberString,
            claimTime: Date(),
            claimMethod: .exclusiveAccess, // Default mock claim method
            claimState: .claimed,
            deviceClass: device.deviceClass,
            deviceSubclass: device.deviceSubClass,
            deviceProtocol: device.deviceProtocol
        )
        
        // Store claimed device
        claimedDevices[deviceID] = claimedDevice
        claimOperations.append((device: device, timestamp: Date()))
        successfulClaims += 1
        
        return claimedDevice
    }
    
    public func releaseDevice(device: USBDevice) throws {
        let deviceID = "\(device.busID)-\(device.deviceID)"
        methodCalls.append("releaseDevice(\(deviceID))")
        releaseAttempts += 1
        
        // Simulate processing delay if configured
        if configuration.releaseDelay > 0 {
            Thread.sleep(forTimeInterval: configuration.releaseDelay)
        }
        
        // Check if releasing should fail
        if !configuration.shouldSucceedReleasing {
            failedReleases += 1
            throw configuration.releaseError
        }
        
        // Check if device is not claimed
        guard claimedDevices[deviceID] != nil else {
            failedReleases += 1
            throw SystemExtensionError.deviceNotClaimed(deviceID)
        }
        
        // Remove from claimed devices
        claimedDevices.removeValue(forKey: deviceID)
        releaseOperations.append((deviceID: deviceID, timestamp: Date()))
        successfulReleases += 1
    }
    
    public func isDeviceClaimed(deviceID: String) -> Bool {
        methodCalls.append("isDeviceClaimed(\(deviceID))")
        return claimedDevices[deviceID] != nil
    }
    
    public func getClaimedDevice(deviceID: String) -> ClaimedDevice? {
        methodCalls.append("getClaimedDevice(\(deviceID))")
        return claimedDevices[deviceID]
    }
    
    public func getAllClaimedDevices() -> [ClaimedDevice] {
        methodCalls.append("getAllClaimedDevices")
        return Array(claimedDevices.values)
    }
    
    public func restoreClaimedDevices() throws {
        methodCalls.append("restoreClaimedDevices")
        restoreOperations.append(Date())
        
        // Check if restoration should fail
        if !configuration.shouldSucceedRestoration {
            throw configuration.restorationError
        }
        
        // Restore devices from configuration
        for device in configuration.restoredDevices {
            claimedDevices[device.deviceID] = device
        }
    }
    
    public func saveClaimState() throws {
        methodCalls.append("saveClaimState")
        saveOperations.append(Date())
        
        // Check if saving should fail
        if !configuration.shouldSucceedSaving {
            throw configuration.saveError
        }
        
        // Mock implementation - state is already in memory
    }
    
    // MARK: - Mock Control Methods
    
    /// Reset mock to current configuration
    public func resetToConfiguration() {
        claimedDevices.removeAll()
        
        // Add initial claimed devices if configured
        for device in configuration.initialClaimedDevices {
            claimedDevices[device.deviceID] = device
        }
    }
    
    /// Reset all mock state and statistics
    public func reset() {
        configuration = MockConfiguration()
        claimedDevices.removeAll()
        methodCalls.removeAll()
        claimOperations.removeAll()
        releaseOperations.removeAll()
        restoreOperations.removeAll()
        saveOperations.removeAll()
        
        claimAttempts = 0
        successfulClaims = 0
        failedClaims = 0
        releaseAttempts = 0
        successfulReleases = 0
        failedReleases = 0
    }
    
    /// Configure mock to simulate specific error scenarios
    public func configureForErrorScenario(_ scenario: MockErrorScenario) {
        switch scenario {
        case .claimFailure(let error):
            configuration.shouldSucceedClaiming = false
            configuration.claimError = error
            
        case .releaseFailure(let error):
            configuration.shouldSucceedReleasing = false
            configuration.releaseError = error
            
        case .restorationFailure(let error):
            configuration.shouldSucceedRestoration = false
            configuration.restorationError = error
            
        case .saveFailure(let error):
            configuration.shouldSucceedSaving = false
            configuration.saveError = error
            
        case .deviceAlreadyClaimed(let deviceID):
            let mockDevice = createMockClaimedDevice(deviceID: deviceID)
            claimedDevices[deviceID] = mockDevice
            
        case .deviceNotClaimed:
            // Clear all claimed devices to simulate "not claimed" errors
            claimedDevices.removeAll()
        }
    }
    
    /// Configure mock to simulate timing scenarios
    public func configureForTimingScenario(_ scenario: MockTimingScenario) {
        switch scenario {
        case .slowClaiming(let delay):
            configuration.claimDelay = delay
            
        case .slowReleasing(let delay):
            configuration.releaseDelay = delay
            
        case .fastOperations:
            configuration.claimDelay = 0.0
            configuration.releaseDelay = 0.0
        }
    }
    
    /// Add a pre-claimed device for testing scenarios
    public func addPreClaimedDevice(_ device: ClaimedDevice) {
        claimedDevices[device.deviceID] = device
    }
    
    /// Remove a claimed device (simulates external release)
    public func removeClaimedDevice(deviceID: String) {
        claimedDevices.removeValue(forKey: deviceID)
    }
    
    /// Verify that expected method calls were made
    public func verifyMethodCalls(_ expectedCalls: [String]) -> Bool {
        return methodCalls == expectedCalls
    }
    
    /// Get claim success rate for testing statistics
    public var claimSuccessRate: Double {
        return claimAttempts > 0 ? Double(successfulClaims) / Double(claimAttempts) : 0.0
    }
    
    /// Get release success rate for testing statistics
    public var releaseSuccessRate: Double {
        return releaseAttempts > 0 ? Double(successfulReleases) / Double(releaseAttempts) : 0.0
    }
    
    // MARK: - Helper Methods
    
    private func createMockClaimedDevice(deviceID: String) -> ClaimedDevice {
        let components = deviceID.split(separator: "-")
        let busID = String(components.first ?? "1")
        let devID = String(components.last ?? "1")
        
        return ClaimedDevice(
            deviceID: deviceID,
            busID: busID,
            vendorID: 0x1234,
            productID: 0x5678,
            productString: "Mock Device",
            manufacturerString: "Mock Manufacturer",
            serialNumber: "MOCK123456",
            claimTime: Date(),
            claimMethod: .exclusiveAccess,
            claimState: .claimed,
            deviceClass: 0x09,
            deviceSubclass: 0x00,
            deviceProtocol: 0x00
        )
    }
}

// MARK: - Mock Scenario Types

/// Error scenarios for testing error handling
public enum MockErrorScenario {
    case claimFailure(SystemExtensionError)
    case releaseFailure(SystemExtensionError)
    case restorationFailure(SystemExtensionError)
    case saveFailure(SystemExtensionError)
    case deviceAlreadyClaimed(String)
    case deviceNotClaimed
}

/// Timing scenarios for testing performance and timeouts
public enum MockTimingScenario {
    case slowClaiming(TimeInterval)
    case slowReleasing(TimeInterval)
    case fastOperations
}

// MARK: - System Extension Test Fixtures

/// Test fixtures specifically designed for System Extension testing
public struct SystemExtensionTestFixtures {
    
    // MARK: - Standard Test Devices for Claiming
    
    /// USB mouse device for testing HID device claiming
    public static let testMouseDevice = USBDevice(
        busID: "1",
        deviceID: "2",
        vendorID: 0x05ac,
        productID: 0x030d,
        deviceClass: 0x03,
        deviceSubClass: 0x01,
        deviceProtocol: 0x02,
        speed: .low,
        manufacturerString: "Apple Inc.",
        productString: "Magic Mouse",
        serialNumberString: "TEST123456"
    )
    
    /// USB flash drive for testing mass storage device claiming
    public static let testFlashDrive = USBDevice(
        busID: "2",
        deviceID: "1",
        vendorID: 0x0781,
        productID: 0x5567,
        deviceClass: 0x08,
        deviceSubClass: 0x06,
        deviceProtocol: 0x50,
        speed: .high,
        manufacturerString: "SanDisk",
        productString: "Cruzer Blade",
        serialNumberString: "TEST7890123"
    )
    
    /// Arduino device for testing CDC device claiming
    public static let testArduinoDevice = USBDevice(
        busID: "1",
        deviceID: "3",
        vendorID: 0x2341,
        productID: 0x0043,
        deviceClass: 0x02,
        deviceSubClass: 0x00,
        deviceProtocol: 0x00,
        speed: .full,
        manufacturerString: "Arduino LLC",
        productString: "Arduino Uno",
        serialNumberString: "TESTABCDEF"
    )
    
    /// USB hub device for testing hub device claiming
    public static let testHubDevice = USBDevice(
        busID: "3",
        deviceID: "1",
        vendorID: 0x0424,
        productID: 0x2514,
        deviceClass: 0x09,
        deviceSubClass: 0x00,
        deviceProtocol: 0x01,
        speed: .high,
        manufacturerString: "Standard Microsystems Corp.",
        productString: "USB 2.0 Hub",
        serialNumberString: nil
    )
    
    // MARK: - Claimed Device Fixtures
    
    /// Pre-claimed mouse device for testing already-claimed scenarios
    public static let claimedMouseDevice = ClaimedDevice(
        deviceID: "1-2",
        busID: "1",
        vendorID: 0x05ac,
        productID: 0x030d,
        productString: "Magic Mouse",
        manufacturerString: "Apple Inc.",
        serialNumber: "TEST123456",
        claimTime: Date().addingTimeInterval(-300), // Claimed 5 minutes ago
        claimMethod: .exclusiveAccess,
        claimState: .claimed,
        deviceClass: 0x03,
        deviceSubclass: 0x01,
        deviceProtocol: 0x02
    )
    
    /// Pre-claimed flash drive for testing state restoration
    public static let claimedFlashDrive = ClaimedDevice(
        deviceID: "2-1",
        busID: "2",
        vendorID: 0x0781,
        productID: 0x5567,
        productString: "Cruzer Blade",
        manufacturerString: "SanDisk",
        serialNumber: "TEST7890123",
        claimTime: Date().addingTimeInterval(-600), // Claimed 10 minutes ago
        claimMethod: .driverUnbind,
        claimState: .claimed,
        deviceClass: 0x08,
        deviceSubclass: 0x06,
        deviceProtocol: 0x50
    )
    
    // MARK: - Device Collections
    
    /// Collection of standard test devices
    public static let standardTestDevices: [USBDevice] = [
        testMouseDevice,
        testFlashDrive,
        testArduinoDevice,
        testHubDevice
    ]
    
    /// Collection of pre-claimed devices for state restoration testing
    public static let preClaimedDevices: [ClaimedDevice] = [
        claimedMouseDevice,
        claimedFlashDrive
    ]
    
    /// Empty collections for boundary testing
    public static let noDevices: [USBDevice] = []
    public static let noClaimedDevices: [ClaimedDevice] = []
    
    // MARK: - Error Testing Devices
    
    /// Device with problematic vendor/product ID for error testing
    public static let problematicDevice = USBDevice(
        busID: "99",
        deviceID: "99",
        vendorID: 0x0000,
        productID: 0x0000,
        deviceClass: 0xFF,
        deviceSubClass: 0xFF,
        deviceProtocol: 0xFF,
        speed: .unknown,
        manufacturerString: nil,
        productString: nil,
        serialNumberString: nil
    )
    
    // MARK: - Helper Methods
    
    /// Create a custom test device with specified properties
    public static func customTestDevice(
        busID: String = "1",
        deviceID: String = "1",
        vendorID: UInt16 = 0x1234,
        productID: UInt16 = 0x5678,
        deviceClass: UInt8 = 0x09,
        deviceSubClass: UInt8 = 0x00,
        deviceProtocol: UInt8 = 0x00,
        speed: USBSpeed = .full,
        manufacturerString: String? = "Test Manufacturer",
        productString: String? = "Test Product",
        serialNumberString: String? = "TEST123456"
    ) -> USBDevice {
        return USBDevice(
            busID: busID,
            deviceID: deviceID,
            vendorID: vendorID,
            productID: productID,
            deviceClass: deviceClass,
            deviceSubClass: deviceSubClass,
            deviceProtocol: deviceProtocol,
            speed: speed,
            manufacturerString: manufacturerString,
            productString: productString,
            serialNumberString: serialNumberString
        )
    }
    
    /// Create a custom claimed device for testing scenarios
    public static func customClaimedDevice(
        deviceID: String = "1-1",
        busID: String = "1",
        vendorID: UInt16 = 0x1234,
        productID: UInt16 = 0x5678,
        claimTime: Date = Date(),
        claimMethod: DeviceClaimMethod = .exclusiveAccess,
        claimState: DeviceClaimState = .claimed
    ) -> ClaimedDevice {
        return ClaimedDevice(
            deviceID: deviceID,
            busID: busID,
            vendorID: vendorID,
            productID: productID,
            productString: "Test Product",
            manufacturerString: "Test Manufacturer",
            serialNumber: "TEST123456",
            claimTime: claimTime,
            claimMethod: claimMethod,
            claimState: claimState,
            deviceClass: 0x09,
            deviceSubclass: 0x00,
            deviceProtocol: 0x00
        )
    }
    
    /// Generate multiple test devices for load testing
    public static func generateMultipleDevices(count: Int) -> [USBDevice] {
        var devices: [USBDevice] = []
        
        for i in 1...count {
            let busID = String((i - 1) / 10 + 1)
            let deviceID = String((i - 1) % 10 + 1)
            
            devices.append(USBDevice(
                busID: busID,
                deviceID: deviceID,
                vendorID: UInt16(0x1000 + i),
                productID: UInt16(0x2000 + i),
                deviceClass: 0x09,
                deviceSubClass: 0x00,
                deviceProtocol: 0x00,
                speed: .full,
                manufacturerString: "Test Manufacturer \(i)",
                productString: "Test Product \(i)",
                serialNumberString: "TEST\(String(format: "%06d", i))"
            ))
        }
        
        return devices
    }
}