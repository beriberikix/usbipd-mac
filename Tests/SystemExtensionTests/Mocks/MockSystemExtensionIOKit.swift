// MockSystemExtensionIOKit.swift
// Enhanced IOKit mock interface for System Extension testing

import Foundation
import IOKit
import IOKit.usb
import Common
import USBIPDCore
@testable import SystemExtension

// MARK: - Enhanced Mock IOKit Interface for System Extension

/// Enhanced IOKit mock interface with System Extension specific features
/// Provides device claiming simulation for System Extension testing
public class MockSystemExtensionIOKit {
    
    // MARK: - System Extension Mock State
    
    /// Devices that can be successfully claimed
    public var claimableDevices: Set<io_service_t> = []
    
    /// Devices that are currently claimed (and should not be claimable)
    public var alreadyClaimedDevices: Set<io_service_t> = []
    
    /// Devices that should fail claiming with specific errors
    public var deviceClaimErrors: [io_service_t: kern_return_t] = [:]
    
    /// Devices that should fail releasing with specific errors  
    public var deviceReleaseErrors: [io_service_t: kern_return_t] = [:]
    
    /// Track device claiming operations for verification
    public var deviceClaimCalls: [io_service_t] = []
    public var deviceReleaseCalls: [io_service_t] = []
    
    /// Simulate exclusive access checks
    public var exclusiveAccessChecks: [io_service_t] = []
    public var exclusiveAccessResults: [io_service_t: Bool] = [:]
    
    /// Simulate driver unbinding operations
    public var driverUnbindCalls: [io_service_t] = []
    public var driverUnbindResults: [io_service_t: kern_return_t] = [:]
    
    /// Current claim method being tested
    public var currentClaimMethod: DeviceClaimMethod = .exclusiveAccess
    
    // MARK: - Basic Mock Properties
    
    /// Mock service value for generating service identifiers  
    public let mockServiceValue: UInt32 = 0x12345678
    
    /// Mock devices for testing
    public var mockDevices: [USBDevice] = []
    
    // MARK: - Enhanced Mock Configuration
    
    public init() {
        setupDefaultClaimableDevices()
    }
    
    public func reset() {
        claimableDevices.removeAll()
        alreadyClaimedDevices.removeAll()
        deviceClaimErrors.removeAll()
        deviceReleaseErrors.removeAll()
        deviceClaimCalls.removeAll()
        deviceReleaseCalls.removeAll()
        exclusiveAccessChecks.removeAll()
        exclusiveAccessResults.removeAll()
        driverUnbindCalls.removeAll()
        driverUnbindResults.removeAll()
        currentClaimMethod = .exclusiveAccess
        
        setupDefaultClaimableDevices()
    }
    
    // MARK: - System Extension Specific Mock Methods
    
    /// Configure a device to be successfully claimable
    public func makeDeviceClaimable(service: io_service_t) {
        claimableDevices.insert(service)
        alreadyClaimedDevices.remove(service)
        deviceClaimErrors.removeValue(forKey: service)
    }
    
    /// Configure a device to be already claimed
    public func makeDeviceAlreadyClaimed(service: io_service_t) {
        alreadyClaimedDevices.insert(service)
        claimableDevices.remove(service)
    }
    
    /// Configure a device to fail claiming with specific error
    public func makeDeviceClaimFail(service: io_service_t, error: kern_return_t) {
        deviceClaimErrors[service] = error
        claimableDevices.remove(service)
    }
    
    /// Configure a device to fail releasing with specific error
    public func makeDeviceReleaseFail(service: io_service_t, error: kern_return_t) {
        deviceReleaseErrors[service] = error
    }
    
    /// Simulate device claiming operation
    public func simulateDeviceClaim(service: io_service_t) -> kern_return_t {
        deviceClaimCalls.append(service)
        
        // Check if device should fail claiming
        if let error = deviceClaimErrors[service] {
            return error
        }
        
        // Check if device is already claimed
        if alreadyClaimedDevices.contains(service) {
            return KERN_RESOURCE_SHORTAGE // Simulate "device busy" error
        }
        
        // Check if device is claimable
        if claimableDevices.contains(service) {
            alreadyClaimedDevices.insert(service)
            claimableDevices.remove(service)
            return KERN_SUCCESS
        }
        
        // Device not found or not claimable
        return KERN_FAILURE
    }
    
    /// Simulate device releasing operation
    public func simulateDeviceRelease(service: io_service_t) -> kern_return_t {
        deviceReleaseCalls.append(service)
        
        // Check if device should fail releasing
        if let error = deviceReleaseErrors[service] {
            return error
        }
        
        // Check if device is actually claimed
        if alreadyClaimedDevices.contains(service) {
            alreadyClaimedDevices.remove(service)
            claimableDevices.insert(service)
            return KERN_SUCCESS
        }
        
        // Device not claimed
        return KERN_INVALID_ARGUMENT
    }
    
    /// Simulate exclusive access check
    public func simulateExclusiveAccessCheck(service: io_service_t) -> Bool {
        exclusiveAccessChecks.append(service)
        
        // Return configured result or default based on claim status
        if let result = exclusiveAccessResults[service] {
            return result
        }
        
        // Default: can get exclusive access if device is claimable
        return claimableDevices.contains(service)
    }
    
    /// Simulate driver unbinding operation
    public func simulateDriverUnbind(service: io_service_t) -> kern_return_t {
        driverUnbindCalls.append(service)
        
        // Return configured result or success by default
        return driverUnbindResults[service] ?? KERN_SUCCESS
    }
    
    /// Configure exclusive access result for a device
    public func setExclusiveAccessResult(service: io_service_t, canAccess: Bool) {
        exclusiveAccessResults[service] = canAccess
    }
    
    /// Configure driver unbind result for a device
    public func setDriverUnbindResult(service: io_service_t, result: kern_return_t) {
        driverUnbindResults[service] = result
    }
    
    // MARK: - Test Scenario Helpers
    
    /// Set up devices for a successful claiming scenario
    public func setupSuccessfulClaimingScenario() {
        reset()
        
        // Add mock devices that can be successfully claimed
        for i in 0..<mockDevices.count {
            let service = io_service_t(mockServiceValue + UInt32(i))
            makeDeviceClaimable(service: service)
        }
    }
    
    /// Set up devices for a failed claiming scenario
    public func setupFailedClaimingScenario(error: kern_return_t = KERN_FAILURE) {
        reset()
        
        // Add mock devices that will fail to claim
        for i in 0..<mockDevices.count {
            let service = io_service_t(mockServiceValue + UInt32(i))
            makeDeviceClaimFail(service: service, error: error)
        }
    }
    
    /// Set up devices for an already claimed scenario
    public func setupAlreadyClaimedScenario() {
        reset()
        
        // Add mock devices that are already claimed
        for i in 0..<mockDevices.count {
            let service = io_service_t(mockServiceValue + UInt32(i))
            makeDeviceAlreadyClaimed(service: service)
        }
    }
    
    /// Set up mixed scenario with some claimable, some claimed, some failing
    public func setupMixedClaimingScenario() {
        reset()
        
        for i in 0..<mockDevices.count {
            let service = io_service_t(mockServiceValue + UInt32(i))
            
            switch i % 3 {
            case 0:
                makeDeviceClaimable(service: service)
            case 1:
                makeDeviceAlreadyClaimed(service: service)
            case 2:
                makeDeviceClaimFail(service: service, error: KERN_PROTECTION_FAILURE)
            default:
                break
            }
        }
    }
    
    // MARK: - Verification Methods
    
    /// Verify that device claiming was attempted for expected services
    public func verifyDeviceClaimAttempts(_ expectedServices: [io_service_t]) -> Bool {
        return deviceClaimCalls == expectedServices
    }
    
    /// Verify that device releasing was attempted for expected services
    public func verifyDeviceReleaseAttempts(_ expectedServices: [io_service_t]) -> Bool {
        return deviceReleaseCalls == expectedServices
    }
    
    /// Verify that exclusive access was checked for expected services
    public func verifyExclusiveAccessChecks(_ expectedServices: [io_service_t]) -> Bool {
        return exclusiveAccessChecks == expectedServices
    }
    
    /// Verify that driver unbinding was attempted for expected services
    public func verifyDriverUnbindAttempts(_ expectedServices: [io_service_t]) -> Bool {
        return driverUnbindCalls == expectedServices
    }
    
    /// Get the current claim status for a service
    public func getClaimStatus(service: io_service_t) -> DeviceClaimStatus {
        if alreadyClaimedDevices.contains(service) {
            return .claimed
        } else if claimableDevices.contains(service) {
            return .available
        } else if deviceClaimErrors[service] != nil {
            return .error
        } else {
            return .unknown
        }
    }
    
    /// Get statistics for mock operations
    public func getClaimingStatistics() -> ClaimingStatistics {
        return ClaimingStatistics(
            totalClaimAttempts: deviceClaimCalls.count,
            totalReleaseAttempts: deviceReleaseCalls.count,
            exclusiveAccessChecks: exclusiveAccessChecks.count,
            driverUnbindAttempts: driverUnbindCalls.count,
            currentlyClaimedDevices: alreadyClaimedDevices.count,
            availableDevices: claimableDevices.count
        )
    }
    
    // MARK: - Private Helper Methods
    
    private func setupDefaultClaimableDevices() {
        // Create some mock devices
        for i in 0..<5 {
            let mockDevice = USBDevice(
                busID: "1",
                deviceID: String(i + 1),
                vendorID: UInt16(0x1234 + i),
                productID: UInt16(0x5678 + i),
                deviceClass: 0x09,
                deviceSubClass: 0x00,
                deviceProtocol: 0x00,
                speed: .high,
                manufacturerString: "Mock Manufacturer \(i)",
                productString: "Mock Device \(i)",
                serialNumberString: "MOCK\(i)123"
            )
            mockDevices.append(mockDevice)
            
            // By default, make all mock devices claimable
            let service = io_service_t(mockServiceValue + UInt32(i))
            claimableDevices.insert(service)
        }
    }
}

// MARK: - Supporting Types

/// Status of a device for claiming purposes
public enum DeviceClaimStatus {
    case available      // Device can be claimed
    case claimed        // Device is already claimed
    case error          // Device has claiming errors
    case unknown        // Device status unknown
}

/// Statistics for mock claiming operations
public struct ClaimingStatistics {
    public let totalClaimAttempts: Int
    public let totalReleaseAttempts: Int
    public let exclusiveAccessChecks: Int
    public let driverUnbindAttempts: Int
    public let currentlyClaimedDevices: Int
    public let availableDevices: Int
    
    public init(
        totalClaimAttempts: Int,
        totalReleaseAttempts: Int,
        exclusiveAccessChecks: Int,
        driverUnbindAttempts: Int,
        currentlyClaimedDevices: Int,
        availableDevices: Int
    ) {
        self.totalClaimAttempts = totalClaimAttempts
        self.totalReleaseAttempts = totalReleaseAttempts
        self.exclusiveAccessChecks = exclusiveAccessChecks
        self.driverUnbindAttempts = driverUnbindAttempts
        self.currentlyClaimedDevices = currentlyClaimedDevices
        self.availableDevices = availableDevices
    }
}

// MARK: - Test Scenario Configurations

/// Pre-defined test scenario configurations for common testing patterns
public struct SystemExtensionTestScenarios {
    
    /// Scenario: All devices can be successfully claimed
    public static func allDevicesClaimable(mockIOKit: MockSystemExtensionIOKit) {
        mockIOKit.setupSuccessfulClaimingScenario()
    }
    
    /// Scenario: All devices are already claimed by other processes
    public static func allDevicesAlreadyClaimed(mockIOKit: MockSystemExtensionIOKit) {
        mockIOKit.setupAlreadyClaimedScenario()
    }
    
    /// Scenario: All devices fail claiming due to permission issues
    public static func allDevicesPermissionDenied(mockIOKit: MockSystemExtensionIOKit) {
        mockIOKit.setupFailedClaimingScenario(error: KERN_PROTECTION_FAILURE)
    }
    
    /// Scenario: Mixed results - some succeed, some fail, some already claimed
    public static func mixedClaimingResults(mockIOKit: MockSystemExtensionIOKit) {
        mockIOKit.setupMixedClaimingScenario()
    }
    
    /// Scenario: Exclusive access fails for all devices
    public static func exclusiveAccessDenied(mockIOKit: MockSystemExtensionIOKit) {
        mockIOKit.setupSuccessfulClaimingScenario()
        
        // Configure exclusive access to fail for all devices
        for i in 0..<5 {
            let service = io_service_t(mockIOKit.mockServiceValue + UInt32(i))
            mockIOKit.setExclusiveAccessResult(service: service, canAccess: false)
        }
    }
    
    /// Scenario: Driver unbinding fails for all devices
    public static func driverUnbindFailure(mockIOKit: MockSystemExtensionIOKit) {
        mockIOKit.setupSuccessfulClaimingScenario()
        
        // Configure driver unbind to fail for all devices
        for i in 0..<5 {
            let service = io_service_t(mockIOKit.mockServiceValue + UInt32(i))
            mockIOKit.setDriverUnbindResult(service: service, result: KERN_PROTECTION_FAILURE)
        }
    }
}