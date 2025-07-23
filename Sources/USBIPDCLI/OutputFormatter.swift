// OutputFormatter.swift
// Output formatting for USB/IP daemon CLI

import Foundation
import USBIPDCore

/// Protocol for formatting output
public protocol OutputFormatter {
    /// Format a list of USB devices for display
    func formatDeviceList(_ devices: [USBDevice]) -> String
    
    /// Format a single USB device for display
    func formatDevice(_ device: USBDevice, detailed: Bool) -> String
    
    /// Format an error message
    func formatError(_ error: Error) -> String
    
    /// Format a success message
    func formatSuccess(_ message: String) -> String
}

/// Linux-compatible output formatter
public class LinuxCompatibleOutputFormatter: OutputFormatter {
    public init() {}
    
    /// Format a list of USB devices in a style compatible with Linux usbipd
    public func formatDeviceList(_ devices: [USBDevice]) -> String {
        var output = "Local USB Device(s)\n"
        output += "==================\n"
        
        if devices.isEmpty {
            output += "No USB devices found.\n"
            return output
        }
        
        output += "Busid  Dev-Node                                    USB Device Information\n"
        output += "------------------------------------------------------------------------------------\n"
        
        for device in devices {
            output += formatDeviceListEntry(device)
        }
        
        return output
    }
    
    /// Format a single device for the device list
    private func formatDeviceListEntry(_ device: USBDevice) -> String {
        let busid = "\(device.busID)-\(device.deviceID)"
        let devNode = "/dev/bus/usb/\(device.busID.padding(toLength: 3, withPad: "0", startingAt: 0))/\(device.deviceID.padding(toLength: 3, withPad: "0", startingAt: 0))"
        
        var deviceInfo = "\(device.vendorID.hexString):\(device.productID.hexString)"
        if let productString = device.productString {
            deviceInfo += " (\(productString))"
        }
        
        return "\(busid.padding(toLength: 6, withPad: " ", startingAt: 0))  \(devNode.padding(toLength: 44, withPad: " ", startingAt: 0))  \(deviceInfo)\n"
    }
    
    /// Format a single USB device with detailed information
    public func formatDevice(_ device: USBDevice, detailed: Bool) -> String {
        let busid = "\(device.busID)-\(device.deviceID)"
        
        if !detailed {
            return formatDeviceListEntry(device)
        }
        
        var output = "Device: \(busid)\n"
        output += "  Vendor ID: \(device.vendorID.hexString)\n"
        output += "  Product ID: \(device.productID.hexString)\n"
        
        if let manufacturer = device.manufacturerString {
            output += "  Manufacturer: \(manufacturer)\n"
        }
        
        if let product = device.productString {
            output += "  Product: \(product)\n"
        }
        
        if let serial = device.serialNumberString {
            output += "  Serial Number: \(serial)\n"
        }
        
        output += "  Class: \(String(format: "%02x", device.deviceClass))\n"
        output += "  Subclass: \(String(format: "%02x", device.deviceSubClass))\n"
        output += "  Protocol: \(String(format: "%02x", device.deviceProtocol))\n"
        output += "  Speed: \(formatSpeed(device.speed))\n"
        
        return output
    }
    
    /// Format USB speed as a human-readable string
    private func formatSpeed(_ speed: USBSpeed) -> String {
        switch speed {
        case .unknown:
            return "Unknown"
        case .low:
            return "Low (1.5 Mbps)"
        case .full:
            return "Full (12 Mbps)"
        case .high:
            return "High (480 Mbps)"
        case .superSpeed:
            return "Super (5 Gbps)"
        }
    }
    
    /// Format an error message
    public func formatError(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return "Error: \(description)"
        } else {
            return "Error: \(error.localizedDescription)"
        }
    }
    
    /// Format a success message
    public func formatSuccess(_ message: String) -> String {
        return message
    }
}

/// Default implementation of OutputFormatter
public class DefaultOutputFormatter: OutputFormatter {
    public init() {}
    
    /// Format a list of USB devices
    public func formatDeviceList(_ devices: [USBDevice]) -> String {
        var output = "Local USB Device(s)\n"
        output += "==================\n"
        output += "Busid  Dev-Node                                    USB Device Information\n"
        output += "------------------------------------------------------------------------------------\n"
        
        for device in devices {
            let busid = "\(device.busID)-\(device.deviceID)"
            let devNode = "/dev/bus/usb/\(device.busID.padding(toLength: 3, withPad: "0", startingAt: 0))/\(device.deviceID.padding(toLength: 3, withPad: "0", startingAt: 0))"
            
            var deviceInfo = "\(device.vendorID.hexString):\(device.productID.hexString)"
            if let productString = device.productString {
                deviceInfo += " (\(productString))"
            }
            
            output += "\(busid.padding(toLength: 6, withPad: " ", startingAt: 0))  \(devNode.padding(toLength: 44, withPad: " ", startingAt: 0))  \(deviceInfo)\n"
        }
        
        return output
    }
    
    /// Format a single USB device
    public func formatDevice(_ device: USBDevice, detailed: Bool) -> String {
        let busid = "\(device.busID)-\(device.deviceID)"
        let devNode = "/dev/bus/usb/\(device.busID.padding(toLength: 3, withPad: "0", startingAt: 0))/\(device.deviceID.padding(toLength: 3, withPad: "0", startingAt: 0))"
        
        var deviceInfo = "\(device.vendorID.hexString):\(device.productID.hexString)"
        if let productString = device.productString {
            deviceInfo += " (\(productString))"
        }
        
        return "\(busid)  \(devNode)  \(deviceInfo)"
    }
    
    /// Format an error message
    public func formatError(_ error: Error) -> String {
        return "Error: \(error.localizedDescription)"
    }
    
    /// Format a success message
    public func formatSuccess(_ message: String) -> String {
        return message
    }
}

/// Extension to format UInt16 as hex string
extension UInt16 {
    var hexString: String {
        return String(format: "%04x", self)
    }
}