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
        log("Processing incoming request", .debug)
        
        do {
            // Validate that data contains a valid USB/IP header
            log("Validating USB/IP header", .debug)
            let header = try USBIPMessageDecoder.validateHeader(in: data)
            
            log("Received request with command: \(header.command)", .info)
            
            // Process based on command type
            switch header.command {
            case .requestDeviceList:
                log("Processing device list request", .debug)
                return try handleDeviceListRequest(data)
                
            case .requestDeviceImport:
                log("Processing device import request", .debug)
                return try handleDeviceImportRequest(data)
                
            default:
                // We should not receive reply messages as requests
                log("Received unsupported command: \(header.command)", .warning)
                throw USBIPProtocolError.unsupportedCommand(header.command.rawValue)
            }
        } catch {
            log("Error processing request: \(error.localizedDescription)", .error)
            log("Request data size: \(data.count) bytes", .debug)
            
            if let protocolError = error as? USBIPProtocolError {
                log("Protocol error details: \(protocolError)", .error)
            }
            
            throw error
        }
    }
    
    /// Handle a device list request
    private func handleDeviceListRequest(_ data: Data) throws -> Data {
        // Decode the request
        log("Decoding device list request", .debug)
        _ = try USBIPMessageDecoder.decodeDeviceListRequest(from: data)
        
        log("Processing device list request", .debug)
        
        do {
            // Get the list of devices from the device discovery
            log("Discovering USB devices", .debug)
            let devices = try deviceDiscovery.discoverDevices()
            
            log("Found \(devices.count) USB devices", .info)
            
            // Convert USBDevice objects to USBIPExportedDevice objects
            log("Converting device information to USB/IP format", .debug)
            let exportedDevices = devices.map { device -> USBIPExportedDevice in
                let exportedDevice = USBIPExportedDevice(
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
                
                log("Prepared device for response", .debug, [
                    "busID": device.busID,
                    "deviceID": device.deviceID,
                    "vendorID": String(format: "0x%04x", device.vendorID),
                    "productID": String(format: "0x%04x", device.productID)
                ])
                
                return exportedDevice
            }
            
            // Create and encode the response
            log("Creating device list response", .debug)
            let response = DeviceListResponse(
                header: USBIPHeader(
                    command: .replyDeviceList,
                    status: 0 // Success
                ),
                devices: exportedDevices
            )
            
            log("Sending device list response with \(exportedDevices.count) devices", .info)
            
            return try USBIPMessageEncoder.encode(response)
        } catch {
            log("Error handling device list request: \(error.localizedDescription)", .error)
            
            if let deviceError = error as? DeviceError {
                log("Device error details: \(deviceError)", .error)
            } else if let protocolError = error as? USBIPProtocolError {
                log("Protocol error details: \(protocolError)", .error)
            }
            
            // Create an error response
            log("Creating error response for device list request", .debug)
            let response = DeviceListResponse(
                header: USBIPHeader(
                    command: .replyDeviceList,
                    status: 1 // Error
                ),
                devices: []
            )
            
            log("Sending error response for device list request", .info)
            return try USBIPMessageEncoder.encode(response)
        }
    }
    
    /// Handle a device import request
    private func handleDeviceImportRequest(_ data: Data) throws -> Data {
        // Decode the request
        log("Decoding device import request", .debug)
        let request = try USBIPMessageDecoder.decodeDeviceImportRequest(from: data)
        
        log("Processing device import request for busID: \(request.busID)", .info)
        
        do {
            // Parse the busID to extract deviceID (assuming format like "1-1:1.0")
            log("Parsing busID: \(request.busID)", .debug)
            let components = request.busID.split(separator: ":")
            guard components.count >= 1 else {
                log("Invalid busID format", .error, ["busID": request.busID])
                throw DeviceError.deviceNotFound("Invalid busID format: \(request.busID)")
            }
            
            let busID = String(components[0])
            let deviceID = components.count > 1 ? String(components[1]) : "1.0" // Default deviceID if not specified
            
            log("Looking for device", .debug, ["busID": busID, "deviceID": deviceID])
            
            // Get the device from the device discovery
            guard let device = try deviceDiscovery.getDevice(busID: busID, deviceID: deviceID) else {
                log("Device not found", .error, ["busID": busID, "deviceID": deviceID])
                throw DeviceError.deviceNotFound("Device not found: \(request.busID)")
            }
            
            log("Found requested device", .info, [
                "busID": device.busID,
                "deviceID": device.deviceID,
                "vendorID": String(format: "0x%04x", device.vendorID),
                "productID": String(format: "0x%04x", device.productID),
                "product": device.productString ?? "Unknown"
            ])
            
            // Create device info for the response
            log("Creating device info for response", .debug)
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
            log("Creating device import response", .debug)
            let response = DeviceImportResponse(
                header: USBIPHeader(
                    command: .replyDeviceImport,
                    status: 0 // Success
                ),
                status: 0, // Success
                deviceInfo: deviceInfo
            )
            
            log("Sending successful device import response", .info, [
                "busID": device.busID,
                "deviceID": device.deviceID,
                "vendorID": String(format: "0x%04x", device.vendorID),
                "productID": String(format: "0x%04x", device.productID)
            ])
            
            return try USBIPMessageEncoder.encode(response)
        } catch {
            log("Error handling device import request: \(error.localizedDescription)", .error)
            
            if let deviceError = error as? DeviceError {
                log("Device error details: \(deviceError)", .error)
            } else if let protocolError = error as? USBIPProtocolError {
                log("Protocol error details: \(protocolError)", .error)
            }
            
            // Create an error response
            log("Creating error response for device import request", .debug)
            let response = DeviceImportResponse(
                header: USBIPHeader(
                    command: .replyDeviceImport,
                    status: 1 // Error
                ),
                status: 1, // Error
                deviceInfo: nil
            )
            
            log("Sending error response for device import request", .info, ["busID": request.busID])
            return try USBIPMessageEncoder.encode(response)
        }
    }
    
    /// Log a message with the specified level
    private func log(_ message: String, _ level: LogLevel, _ context: [String: String] = [:]) {
        logger?(message, level)
    }
}