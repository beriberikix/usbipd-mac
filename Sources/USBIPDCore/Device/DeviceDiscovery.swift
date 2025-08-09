// DeviceDiscovery.swift
// USB device discovery using IOKit

import Foundation
import Common

/// Protocol for USB device discovery
public protocol DeviceDiscovery {
    /// Discover all USB devices connected to the system
    func discoverDevices() throws -> [USBDevice]
    
    /// Get a specific device by bus ID and device ID
    func getDevice(busID: String, deviceID: String) throws -> USBDevice?
    
    /// Start monitoring for device notifications
    func startNotifications() throws
    
    /// Stop monitoring for device notifications
    func stopNotifications()
    
    /// Callback for device connection events
    var onDeviceConnected: ((USBDevice) -> Void)? { get set }
    
    /// Callback for device disconnection events
    var onDeviceDisconnected: ((USBDevice) -> Void)? { get set }
}

