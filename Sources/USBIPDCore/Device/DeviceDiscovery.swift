// DeviceDiscovery.swift
// USB device discovery using IOKit

import Foundation

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

/// Protocol for USB device information
public protocol USBDeviceInfo {
    var busID: String { get }
    var deviceID: String { get }
    var vendorID: UInt16 { get }
    var productID: UInt16 { get }
    var deviceClass: UInt8 { get }
    var deviceSubClass: UInt8 { get }
    var deviceProtocol: UInt8 { get }
    var speed: USBSpeed { get }
    var manufacturerString: String? { get }
    var productString: String? { get }
    var serialNumberString: String? { get }
}

/// Represents a USB device
public struct USBDevice: USBDeviceInfo {
    public let busID: String
    public let deviceID: String
    public let vendorID: UInt16
    public let productID: UInt16
    public let deviceClass: UInt8
    public let deviceSubClass: UInt8
    public let deviceProtocol: UInt8
    public let speed: USBSpeed
    public let manufacturerString: String?
    public let productString: String?
    public let serialNumberString: String?
    
    public init(
        busID: String,
        deviceID: String,
        vendorID: UInt16,
        productID: UInt16,
        deviceClass: UInt8,
        deviceSubClass: UInt8,
        deviceProtocol: UInt8,
        speed: USBSpeed,
        manufacturerString: String?,
        productString: String?,
        serialNumberString: String?
    ) {
        self.busID = busID
        self.deviceID = deviceID
        self.vendorID = vendorID
        self.productID = productID
        self.deviceClass = deviceClass
        self.deviceSubClass = deviceSubClass
        self.deviceProtocol = deviceProtocol
        self.speed = speed
        self.manufacturerString = manufacturerString
        self.productString = productString
        self.serialNumberString = serialNumberString
    }
}

/// USB device speed enumeration
public enum USBSpeed: UInt8 {
    case unknown = 0
    case low = 1
    case full = 2
    case high = 3
    case superSpeed = 4
}