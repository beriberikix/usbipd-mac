// RequestProcessor.swift
// Processes USB/IP protocol requests and generates responses

import Foundation
import Common

/// Protocol for handling USB SUBMIT and UNLINK requests
public protocol USBRequestHandlerProtocol {
    /// Handle a USB SUBMIT request and return response data
    func handleSubmitRequest(_ data: Data) throws -> Data
    
    /// Handle a USB UNLINK request and return response data  
    func handleUnlinkRequest(_ data: Data) throws -> Data
    
    /// Validate that a device is accessible for USB operations
    func validateDeviceAccess(_ busID: String) throws -> Bool
}

/// Processes USB/IP protocol requests and generates responses
/// Per-connection protocol state.
///
/// USB/IP changes framing mid-connection and gives no in-band signal that it has done
/// so. Before import, messages use `op_common` — version(2) code(2) status(4). After a
/// successful OP_REQ_IMPORT the *same socket* carries URB traffic framed with
/// `usbip_header_basic` — command(4) seqnum(4) devid(4) direction(4) ep(4), no version.
///
/// The two cannot be told apart from the bytes alone: a CMD_SUBMIT read as op_common
/// yields version 0x0000 and code 0x0001, which is indistinguishable from a malformed
/// handshake message. The receiver has to remember which phase the connection is in,
/// which is why this is state rather than a parsing heuristic.
public final class USBIPConnectionState {
    public enum Phase {
        /// Handshake: device list and import, framed with op_common.
        case handshake
        /// Post-import: URB traffic, framed with usbip_header_basic.
        case attached(busID: String)
    }

    private let lock = NSLock()
    private var _phase: Phase = .handshake

    public init() {}

    public var phase: Phase {
        lock.lock(); defer { lock.unlock() }
        return _phase
    }

    /// Called once OP_REP_IMPORT has been sent successfully.
    public func markAttached(busID: String) {
        lock.lock(); defer { lock.unlock() }
        _phase = .attached(busID: busID)
    }
}

public class RequestProcessor {
    /// Device discovery for USB device enumeration
    private let deviceDiscovery: DeviceDiscovery
    
    /// Device claim manager for device claiming
    private let deviceClaimManager: DeviceClaimManager

    /// Bind allow-list. When nil no filtering is applied, which is the behaviour direct
    /// unit-test construction relies on; the daemon always supplies it.
    private let config: ServerConfig?
    
    /// USB request handler for SUBMIT/UNLINK operations (will be injected later)
    private var usbRequestHandler: USBRequestHandlerProtocol?
    
    /// Logger for error and diagnostic information
    private let logger: ((String, LogLevel) -> Void)?
    
    /// Log levels for the request processor
    public enum LogLevel {
        case debug
        case info
        case warning
        case error
    }
    
    /// Initialize with device discovery and device claim manager
    public init(deviceDiscovery: DeviceDiscovery, deviceClaimManager: DeviceClaimManager, config: ServerConfig? = nil, logger: ((String, LogLevel) -> Void)? = nil) {
        self.config = config
        self.deviceDiscovery = deviceDiscovery
        self.deviceClaimManager = deviceClaimManager
        self.logger = logger
    }
    
    /// Set the USB request handler for processing SUBMIT/UNLINK requests
    public func setUSBRequestHandler(_ handler: USBRequestHandlerProtocol) {
        self.usbRequestHandler = handler
    }
    
    /// Process incoming request data and generate a response
    /// Process a request on a connection with no tracked state.
    ///
    /// Only ever sees the handshake phase, so it cannot handle URB traffic. Retained
    /// for callers that genuinely only exchange device-list requests.
    public func processRequest(_ data: Data) throws -> Data {
        return try processRequest(data, connectionState: USBIPConnectionState())
    }

    /// Process a request in the context of a connection.
    ///
    /// The phase decides how the bytes are framed; see USBIPConnectionState.
    public func processRequest(_ data: Data, connectionState: USBIPConnectionState) throws -> Data {
        if case .attached = connectionState.phase {
            return try processAttachedPhaseRequest(data)
        }
        return try processHandshakeRequest(data, connectionState: connectionState)
    }

    /// URB traffic, framed with usbip_header_basic.
    private func processAttachedPhaseRequest(_ data: Data) throws -> Data {
        let header = try USBIPBasicHeader.decode(from: data)
        log("Received URB command: \(header.command)", .debug)

        switch header.command {
        case .submit:
            return try handleSubmitRequest(data)
        case .unlink:
            return try handleUnlinkRequest(data)
        case .retSubmit, .retUnlink:
            // Replies flow server -> client; receiving one means the peer is confused.
            log("Received a reply command on an attached connection", .warning)
            throw USBIPProtocolError.unsupportedCommand(UInt16(truncatingIfNeeded: header.command.rawValue))
        }
    }

    private func processHandshakeRequest(_ data: Data, connectionState: USBIPConnectionState) throws -> Data {
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
                let response = try handleDeviceImportRequest(data)
                // Everything after a successful import is URB traffic on this same
                // socket, framed differently. Only flip on success: a rejected import
                // leaves the connection in the handshake phase.
                if let importRequest = try? DeviceImportRequest.decode(from: data),
                   let decoded = try? DeviceImportResponse.decode(from: response),
                   decoded.header.status == 0 {
                    log("Connection entering attached phase", .info)
                    connectionState.markAttached(busID: importRequest.busID)
                }
                return response
                
            case .submitRequest:
                log("Processing USB SUBMIT request", .debug)
                return try handleSubmitRequest(data)
                
            case .unlinkRequest:
                log("Processing USB UNLINK request", .debug)
                return try handleUnlinkRequest(data)
                
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
    /// Whether a device has been bound for sharing. Absent config means no filtering.
    private func isDeviceShared(busID: String, deviceID: String) -> Bool {
        guard let config = config else { return true }
        return config.isDeviceAllowed("\(busID)-\(deviceID)")
    }

    private func handleDeviceListRequest(_ data: Data) throws -> Data {
        // Decode the request
        log("Decoding device list request", .debug)
        _ = try USBIPMessageDecoder.decodeDeviceListRequest(from: data)
        
        log("Processing device list request", .debug)
        
        do {
            // Get the list of devices from the device discovery
            log("Discovering USB devices", .debug)
            let allDevices = try deviceDiscovery.discoverDevices()

            // Only advertise devices that were explicitly bound. Without this the list
            // exposed every USB device on the machine regardless of what `bind` had
            // been run on, which made bind and unbind decorative.
            let devices = allDevices.filter { device in
                isDeviceShared(busID: device.busID, deviceID: device.deviceID)
            }

            log("Found \(allDevices.count) USB devices, \(devices.count) shared", .info)
            
            // Convert USBDevice objects to USBIPExportedDevice objects
            log("Converting device information to USB/IP format", .debug)
            let exportedDevices = devices.map { device -> USBIPExportedDevice in
                let exportedDevice = USBIPExportedDevice(
                    path: "/sys/devices/\(device.busID)-\(device.deviceID)",
                    // The busid a client passes to `usbip attach` is the composed
                    // bus-device identifier. Advertising only the bus number made every
                    // device on the host report the same busid, "1", so a client could
                    // not name one to import.
                    busID: "\(device.busID)-\(device.deviceID)",
                    busnum: UInt32(device.busID) ?? 0,
                    devnum: USBIPDeviceIdentity.devnum(forPortPath: device.deviceID) ?? 0,
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
            // Split the busid the client sends back into the bus and device numbers
            // used for lookup. This is the same composed "bus-device" form advertised
            // in the device list — "1-17" for a J-Link on bus 1 — so it splits on the
            // first hyphen.
            //
            // This previously split on ":" and expected "1-1:1.0", a format nothing
            // advertised or sent, so every import fell back to a default deviceID of
            // "1.0" and looked up a device that did not exist.
            log("Parsing busID: \(request.busID)", .debug)
            let parts = request.busID.split(separator: "-", maxSplits: 1)
            guard parts.count == 2 else {
                log("Invalid busID format", .error, ["busID": request.busID])
                throw DeviceError.deviceNotFound("Invalid busID format: \(request.busID)")
            }

            let busID = String(parts[0])
            let deviceID = String(parts[1])
            
            log("Looking for device", .debug, ["busID": busID, "deviceID": deviceID])

            // Refuse devices that were never bound, so an unbound device cannot be
            // imported by guessing its busid even though it is absent from the list.
            guard isDeviceShared(busID: busID, deviceID: deviceID) else {
                log("Device is not shared", .error, ["busID": request.busID])
                throw DeviceError.deviceNotFound("Device not shared: \(request.busID). Run 'usbipd bind \(request.busID)' first.")
            }

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
            
            // Check if device is already claimed
            let deviceIdentifier = "\(device.busID)-\(device.deviceID)"
            if deviceClaimManager.isDeviceClaimed(deviceID: deviceIdentifier) {
                log("Device is already claimed", .info, [
                    "deviceID": deviceIdentifier,
                    "busID": device.busID,
                    "device": device.deviceID
                ])
                
                // Device is already claimed, proceed with import
                log("Proceeding with import of already claimed device", .debug)
            } else {
                // Attempt to claim the device
                log("Attempting to claim device", .info, [
                    "deviceID": deviceIdentifier,
                    "busID": device.busID,
                    "device": device.deviceID
                ])
                
                // A failed claim must not refuse the import.
                //
                // The claim goes through the System Extension, which cannot be
                // activated from a shipping install, and devices are served through
                // IOKit from userspace without it. When the manager stopped being
                // started at launch, this threw for every device and the daemon could
                // serve nothing at all — bind succeeded and attach then failed, which
                // shipped in v0.5.3.
                //
                // Whether a device can actually be claimed is decided by `bind`, which
                // reads real ownership from the IORegistry.
                do {
                    let success = try deviceClaimManager.claimDevice(device)
                    if success {
                        log("Successfully claimed device", .info, [
                            "deviceID": deviceIdentifier
                        ])
                    } else {
                        log("Claim reported failure; serving through IOKit regardless", .debug, [
                            "deviceID": deviceIdentifier
                        ])
                    }
                } catch {
                    // Same reasoning as above: the claim is bookkeeping over a
                    // subsystem that never runs, so its failure is not the client's
                    // problem. Throwing here made every import fail with
                    // "Failed to claim exclusive access".
                    log("Claim unavailable; serving through IOKit regardless", .debug, [
                        "deviceID": deviceIdentifier,
                        "error": error.localizedDescription
                    ])
                }
            }
            
            // Create and encode the response (success)
            log("Creating device import response", .debug)
            // OP_REP_IMPORT carries the full usbip_usb_device on success; a header-only
            // reply leaves the client blocked waiting for 312 bytes.
            let importedDevice = USBIPExportedDevice(
                path: "/sys/devices/\(device.busID)-\(device.deviceID)",
                busID: "\(device.busID)-\(device.deviceID)",
                busnum: UInt32(device.busID) ?? 0,
                devnum: USBIPDeviceIdentity.devnum(forPortPath: device.deviceID) ?? 0,
                speed: UInt32(device.speed.rawValue),
                vendorID: device.vendorID,
                productID: device.productID,
                deviceClass: device.deviceClass,
                deviceSubClass: device.deviceSubClass,
                deviceProtocol: device.deviceProtocol,
                configurationCount: 1,
                configurationValue: 1,
                interfaceCount: 1
            )
            let response = DeviceImportResponse(
                header: USBIPHeader(
                    command: .replyDeviceImport,
                    status: 0 // Success
                ),
                device: importedDevice
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
                )
            )
            
            log("Sending error response for device import request", .info, ["busID": request.busID])
            return try USBIPMessageEncoder.encode(response)
        }
    }
    
    /// Handle a USB SUBMIT request for actual USB I/O operations
    private func handleSubmitRequest(_ data: Data) throws -> Data {
        log("Handling USB SUBMIT request", .debug)
        
        // Ensure USB request handler is available
        guard let handler = usbRequestHandler else {
            log("USB request handler not available", .error)
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        do {
            // Delegate to the USB request handler
            return try handler.handleSubmitRequest(data)
        } catch {
            log("Error in USB SUBMIT request handling: \(error.localizedDescription)", .error)
            
            // Create error response if handler fails
            // This will be implemented when USB message types are available
            throw error
        }
    }
    
    /// Handle a USB UNLINK request for cancelling USB operations
    private func handleUnlinkRequest(_ data: Data) throws -> Data {
        log("Handling USB UNLINK request", .debug)
        
        // Ensure USB request handler is available
        guard let handler = usbRequestHandler else {
            log("USB request handler not available", .error)
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        do {
            // Delegate to the USB request handler
            return try handler.handleUnlinkRequest(data)
        } catch {
            log("Error in USB UNLINK request handling: \(error.localizedDescription)", .error)
            
            // Create error response if handler fails
            // This will be implemented when USB message types are available
            throw error
        }
    }
    
    /// Log a message with the specified level
    private func log(_ message: String, _ level: LogLevel, _ context: [String: String] = [:]) {
        logger?(message, level)
    }
}