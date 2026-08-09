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

/// Records which devices have been offered for sharing, within this process.
///
/// This is the production implementation, and the name is meant literally: nothing is
/// claimed from macOS. usbipd serves devices from userspace through IOKit and takes no
/// exclusive access, because it has none to take. What this tracks is intent, so that
/// callers asking "have I already prepared this device" get a coherent answer.
///
/// It used to be called `MockDeviceClaimManager` while being the default the daemon
/// actually ran with — the real-sounding implementation, `SystemExtensionClaimAdapter`,
/// threw `.extensionNotRunning` on every call because the extension was never started.
/// Three separate call sites had to catch that and carry on, each after a release where
/// treating it as fatal broke the daemon outright.
///
/// Ownership is decided in two places that do reflect reality: `DeviceOwnershipInspector`
/// refuses to bind a device whose interfaces macOS holds, and IOKit refuses
/// `USBInterfaceOpen` on an interface another driver owns.
public class UserspaceDeviceClaimManager: DeviceClaimManager {
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