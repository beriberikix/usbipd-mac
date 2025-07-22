// DeviceMonitor.swift
// Monitors USB device connections and disconnections

import Foundation
import IOKit
import IOKit.usb

/// Class for monitoring USB device connections and disconnections
public class DeviceMonitor {
    
    // MARK: - Types
    
    /// Represents a device event type
    public enum DeviceEventType {
        case connected
        case disconnected
    }
    
    /// Represents a device event
    public struct DeviceEvent {
        public let type: DeviceEventType
        public let device: USBDevice?
        public let timestamp: Date
        
        public init(type: DeviceEventType, device: USBDevice?, timestamp: Date = Date()) {
            self.type = type
            self.device = device
            self.timestamp = timestamp
        }
    }
    
    // MARK: - Properties
    
    /// Callback for device events
    public var onDeviceEvent: ((DeviceEvent) -> Void)?
    
    private var deviceDiscovery: DeviceDiscovery
    private var isMonitoring: Bool = false
    private var knownDevices: [String: USBDevice] = [:]
    
    // MARK: - Initialization
    
    /// Initialize with a device discovery implementation
    public init(deviceDiscovery: DeviceDiscovery) {
        self.deviceDiscovery = deviceDiscovery
        
        // Set up callbacks
        self.deviceDiscovery.onDeviceConnected = { [weak self] device in
            self?.handleDeviceConnected(device)
        }
        
        self.deviceDiscovery.onDeviceDisconnected = { [weak self] device in
            self?.handleDeviceDisconnected(device)
        }
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring for device changes
    public func startMonitoring() throws {
        guard !isMonitoring else { return }
        
        // First, discover all current devices to establish baseline
        let devices = try deviceDiscovery.discoverDevices()
        
        // Store known devices by unique identifier
        for device in devices {
            let key = deviceKey(busID: device.busID, deviceID: device.deviceID)
            knownDevices[key] = device
        }
        
        // Start IOKit notifications
        try deviceDiscovery.startNotifications()
        isMonitoring = true
    }
    
    /// Stop monitoring for device changes
    public func stopMonitoring() {
        guard isMonitoring else { return }
        
        deviceDiscovery.stopNotifications()
        knownDevices.removeAll()
        isMonitoring = false
    }
    
    /// Check if monitoring is active
    public func isActive() -> Bool {
        return isMonitoring
    }
    
    /// Get currently known devices
    public func getKnownDevices() -> [USBDevice] {
        return Array(knownDevices.values)
    }
    
    // MARK: - Private Methods
    
    private func handleDeviceConnected(_ device: USBDevice) {
        let key = deviceKey(busID: device.busID, deviceID: device.deviceID)
        
        // Check if this is a new device
        if knownDevices[key] == nil {
            knownDevices[key] = device
            
            // Notify about the new device
            let event = DeviceEvent(type: .connected, device: device)
            onDeviceEvent?(event)
        }
    }
    
    private func handleDeviceDisconnected(_ device: USBDevice) {
        let key = deviceKey(busID: device.busID, deviceID: device.deviceID)
        
        // Check if this is a known device
        if let knownDevice = knownDevices[key] {
            knownDevices.removeValue(forKey: key)
            
            // Notify about the disconnected device
            let event = DeviceEvent(type: .disconnected, device: knownDevice)
            onDeviceEvent?(event)
        }
    }
    
    private func deviceKey(busID: String, deviceID: String) -> String {
        return "\(busID):\(deviceID)"
    }
}