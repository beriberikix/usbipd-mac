// RequestProcessor.swift
// Processes USB/IP protocol requests and generates responses

import Foundation
import Common

/// Processes USB/IP protocol requests and generates responses
public class RequestProcessor {
    /// Device discovery for USB device enumeration
    private let deviceDiscovery: DeviceDiscovery
    
    /// Logger for error and diagnostic information
    private let logger: ((String, LogLevel) -> Void)?
    
    /// Log levels for the request processor
    public enum LogLevel {
        case debug
        case info
        case warning
        case error
    }
    
    /// Initialize with device discovery
    public init(deviceDiscovery: DeviceDiscovery, logger: ((String, LogLevel) -> Void)? = nil) {
        self.deviceDiscovery = deviceDiscovery
        self.logger = logger
    }
    
    /// Process incoming request data and generate a response
    public func processRequest(_ data: Data) throws -> Data {
        do {
            // Validate that data contains a valid USB/IP header
            let header = try USBIPMessageDecoder.validateHeader(in: data)
            
            // Process based on command type
            switch header.command {
            case .requestDeviceList:
                return try handleDeviceListRequest(data)
                
            case .requestDeviceImport:
                return try handleDeviceImportRequest(data)
                
            default:
                // We should not receive reply messages as requests
                log("Received unsupported command: \(header.command)", .warning)
                throw USBIPProtocolError.unsupportedCommand(header.command.rawValue)
            }
        } catch {
            log("Error processing request: \(error.localizedDescription)", .error)
            throw error
        }
    }
    
    /// Handle a device list request
    private func handleDeviceListRequest(_ data: Data) throws -> Data {
        // Decode the request
        _ = try USBIPMessageDecoder.decodeDeviceListRequest(from: data)
        
        log("Processing device list request", .debug)
        
        do {
            // Get the list of devices from the device discovery
            let devices = try deviceDiscovery.discoverDevices()
            
            // Convert USBDevice objects to USBIPExportedDevice objects
            let exportedDevices = devices.map { device -> USBIPExportedDevice in
                return USBIPExportedDevice(
                    path: "/sys/devices/\(device.busID)/\(device.deviceID)",
                    busID: device.busID,
                    busnum: UInt32(Int(device.busID.split(separator: "-").last ?? "0") ?? 0),
                    devnum: UInt32(Int(device.deviceID.split(separator: ".").last ?? "0") ?? 0),
                    speed: UInt32(device.speed.rawValue),
                    vendorID: device.vendorID,
                    productID: device.productID,
                    deviceClass: device.deviceClass,
                    deviceSubClass: device.deviceSubClass,
                    deviceProtocol: device.deviceProtocol,
                    configurationCount: 1, // Default value for MVP
                    configurationValue: 1, // Default value for MVP
                    interfaceCount: 1      // Default value for MVP
                )
            }
            
            // Create and encode the response
            let response = DeviceListResponse(
                header: USBIPHeader(
                    command: .replyDeviceList,
                    status: 0 // Success
                ),
                devices: exportedDevices
            )
            
            log("Sending device list response with \(exportedDevices.count) devices", .debug)
            
            return try USBIPMessageEncoder.encode(response)
        } catch {
            log("Error handling device list request: \(error.localizedDescription)", .error)
            
            // Create an error response
            let response = DeviceListResponse(
                header: USBIPHeader(
                    command: .replyDeviceList,
                    status: 1 // Error
                ),
                devices: []
            )
            
            return try USBIPMessageEncoder.encode(response)
        }
    }
    
    /// Handle a device import request
    private func handleDeviceImportRequest(_ data: Data) throws -> Data {
        // Decode the request
        let request = try USBIPMessageDecoder.decodeDeviceImportRequest(from: data)
        
        log("Processing device import request for busID: \(request.busID)", .debug)
        
        do {
            // Parse the busID to extract deviceID (assuming format like "1-1:1.0")
            let components = request.busID.split(separator: ":")
            guard components.count >= 1 else {
                throw DeviceError.deviceNotFound("Invalid busID format: \(request.busID)")
            }
            
            let busID = String(components[0])
            let deviceID = components.count > 1 ? String(components[1]) : "1.0" // Default deviceID if not specified
            
            // Get the device from the device discovery
            guard let device = try deviceDiscovery.getDevice(busID: busID, deviceID: deviceID) else {
                throw DeviceError.deviceNotFound("Device not found: \(request.busID)")
            }
            
            // Create device info for the response
            let deviceInfo = USBIPDeviceInfo(
                path: "/sys/devices/\(device.busID)/\(device.deviceID)",
                busID: device.busID,
                busnum: UInt32(Int(device.busID.split(separator: "-").last ?? "0") ?? 0),
                devnum: UInt32(Int(device.deviceID.split(separator: ".").last ?? "0") ?? 0),
                speed: UInt32(device.speed.rawValue),
                vendorID: device.vendorID,
                productID: device.productID,
                deviceClass: device.deviceClass,
                deviceSubClass: device.deviceSubClass,
                deviceProtocol: device.deviceProtocol,
                configurationCount: 1, // Default value for MVP
                configurationValue: 1, // Default value for MVP
                interfaceCount: 1      // Default value for MVP
            )
            
            // Create and encode the response
            let response = DeviceImportResponse(
                header: USBIPHeader(
                    command: .replyDeviceImport,
                    status: 0 // Success
                ),
                status: 0, // Success
                deviceInfo: deviceInfo
            )
            
            log("Sending device import response for device: \(device.busID)", .debug)
            
            return try USBIPMessageEncoder.encode(response)
        } catch {
            log("Error handling device import request: \(error.localizedDescription)", .error)
            
            // Create an error response
            let response = DeviceImportResponse(
                header: USBIPHeader(
                    command: .replyDeviceImport,
                    status: 1 // Error
                ),
                status: 1, // Error
                deviceInfo: nil
            )
            
            return try USBIPMessageEncoder.encode(response)
        }
    }
    
    /// Log a message with the specified level
    private func log(_ message: String, _ level: LogLevel) {
        logger?(message, level)
    }
}