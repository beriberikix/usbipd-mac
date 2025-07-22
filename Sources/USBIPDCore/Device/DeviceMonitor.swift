// DeviceMonitor.swift
// Monitors USB device connections and disconnections

import Foundation
import IOKit
import IOKit.usb
import Common

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
    private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "device-monitor")
    
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
        guard !isMonitoring else {
            logger.debug("Device monitoring already active")
            return
        }
        
        logger.info("Starting device monitoring")
        
        // First, discover all current devices to establish baseline
        logger.debug("Discovering initial devices")
        let devices = try deviceDiscovery.discoverDevices()
        
        // Store known devices by unique identifier
        for device in devices {
            let key = deviceKey(busID: device.busID, deviceID: device.deviceID)
            knownDevices[key] = device
            logger.debug("Added initial device to known devices", context: [
                "busID": device.busID,
                "deviceID": device.deviceID,
                "vendorID": String(format: "0x%04x", device.vendorID),
                "productID": String(format: "0x%04x", device.productID)
            ])
        }
        
        logger.debug("Starting device notifications")
        
        // Start IOKit notifications
        try deviceDiscovery.startNotifications()
        isMonitoring = true
        
        logger.info("Device monitoring started successfully", context: ["initialDeviceCount": devices.count])
    }
    
    /// Stop monitoring for device changes
    public func stopMonitoring() {
        guard isMonitoring else {
            logger.debug("Device monitoring not active")
            return
        }
        
        logger.info("Stopping device monitoring", context: ["knownDeviceCount": knownDevices.count])
        
        deviceDiscovery.stopNotifications()
        knownDevices.removeAll()
        isMonitoring = false
        
        logger.info("Device monitoring stopped")
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
            logger.debug("New device connected", context: [
                "busID": device.busID,
                "deviceID": device.deviceID,
                "vendorID": String(format: "0x%04x", device.vendorID),
                "productID": String(format: "0x%04x", device.productID),
                "product": device.productString ?? "Unknown"
            ])
            
            knownDevices[key] = device
            
            // Notify about the new device
            let event = DeviceEvent(type: .connected, device: device)
            onDeviceEvent?(event)
            
            logger.info("Device connected event processed", context: [
                "busID": device.busID,
                "deviceID": device.deviceID,
                "totalDevices": knownDevices.count
            ])
        } else {
            logger.debug("Ignoring already known device", context: [
                "busID": device.busID,
                "deviceID": device.deviceID
            ])
        }
    }
    
    private func handleDeviceDisconnected(_ device: USBDevice) {
        let key = deviceKey(busID: device.busID, deviceID: device.deviceID)
        
        // Check if this is a known device
        if let knownDevice = knownDevices[key] {
            logger.debug("Known device disconnected", context: [
                "busID": knownDevice.busID,
                "deviceID": knownDevice.deviceID,
                "vendorID": String(format: "0x%04x", knownDevice.vendorID),
                "productID": String(format: "0x%04x", knownDevice.productID)
            ])
            
            knownDevices.removeValue(forKey: key)
            
            // Notify about the disconnected device
            let event = DeviceEvent(type: .disconnected, device: knownDevice)
            onDeviceEvent?(event)
            
            logger.info("Device disconnected event processed", context: [
                "busID": knownDevice.busID,
                "deviceID": knownDevice.deviceID,
                "remainingDevices": knownDevices.count
            ])
        } else {
            logger.debug("Ignoring unknown disconnected device", context: [
                "busID": device.busID,
                "deviceID": device.deviceID
            ])
        }
    }
    
    private func deviceKey(busID: String, deviceID: String) -> String {
        return "\(busID):\(deviceID)"
    }
}