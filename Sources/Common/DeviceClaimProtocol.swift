// DeviceClaimProtocol.swift
// Protocol for device claiming operations to avoid circular dependencies

import Foundation

/// Protocol for device claiming operations
public protocol DeviceClaimManager {
    /// Check if a device is currently claimed
    /// - Parameter deviceID: Device identifier (busID-deviceID format)
    /// - Returns: True if device is claimed, false otherwise
    func isDeviceClaimed(deviceID: String) -> Bool
    
    /// Claim exclusive access to a USB device
    /// - Parameter device: The USB device to claim
    /// - Returns: True if successfully claimed, false otherwise
    /// - Throws: Error if claiming fails
    func claimDevice(_ device: USBDevice) throws -> Bool
    
    /// Release a previously claimed USB device
    /// - Parameter device: The USB device to release
    /// - Throws: Error if release fails
    func releaseDevice(_ device: USBDevice) throws
}

/// Mock device claim manager for testing
public class MockDeviceClaimManager: DeviceClaimManager {
    private var claimedDevices: Set<String> = []
    
    public init() {}
    
    public func isDeviceClaimed(deviceID: String) -> Bool {
        return claimedDevices.contains(deviceID)
    }
    
    public func claimDevice(_ device: USBDevice) throws -> Bool {
        let deviceID = "\(device.busID)-\(device.deviceID)"
        claimedDevices.insert(deviceID)
        return true
    }
    
    public func releaseDevice(_ device: USBDevice) throws {
        let deviceID = "\(device.busID)-\(device.deviceID)"
        claimedDevices.remove(deviceID)
    }
}