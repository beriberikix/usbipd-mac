// SystemExtensionClaimAdapter.swift
// Adapter to allow SystemExtensionManager to conform to DeviceClaimManager protocol

import Foundation
import Common

/// Adapter that allows SystemExtensionManager to be used as a DeviceClaimManager
public class SystemExtensionClaimAdapter: DeviceClaimManager {
    private let systemExtensionManager: SystemExtensionManager
    
    public init(systemExtensionManager: SystemExtensionManager) {
        self.systemExtensionManager = systemExtensionManager
    }
    
    public func isDeviceClaimed(deviceID: String) -> Bool {
        return systemExtensionManager.isDeviceClaimed(deviceID: deviceID)
    }
    
    public func claimDevice(_ device: USBDevice) throws -> Bool {
        do {
            _ = try systemExtensionManager.claimDevice(device)
            return true
        } catch {
            throw error
        }
    }
    
    public func releaseDevice(_ device: USBDevice) throws {
        try systemExtensionManager.releaseDevice(device)
    }
}