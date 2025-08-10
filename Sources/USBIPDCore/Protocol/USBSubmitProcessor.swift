// USBSubmitProcessor.swift
// Processes USB/IP SUBMIT requests and coordinates USB transfer execution

import Foundation
import Common

/// Processor for USB/IP SUBMIT requests with URB lifecycle management
public class USBSubmitProcessor {
    /// Active USB Request Blocks (URBs) tracking with status
    private var activeURBs: [UInt32: (urb: USBRequestBlock, status: URBStatus)] = [:]
    private let urbQueue = DispatchQueue(label: "com.usbipd.mac.urb", attributes: .concurrent)
    
    /// Device communicator for executing USB transfers
    private weak var deviceCommunicator: USBDeviceCommunicatorProtocol?
    
    /// Logger for error and diagnostic information
    private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "usb-submit-processor")
    
    /// Maximum concurrent USB requests
    private let maxConcurrentRequests: Int = 64
    
    /// Initialize with device communicator
    public init(deviceCommunicator: USBDeviceCommunicatorProtocol? = nil) {
        self.deviceCommunicator = deviceCommunicator
    }
    
    /// Set the device communicator
    public func setDeviceCommunicator(_ communicator: USBDeviceCommunicatorProtocol) {
        self.deviceCommunicator = communicator
    }
    
    /// Process a USB SUBMIT request and return response data
    public func processSubmitRequest(_ data: Data) async throws -> Data {
        logger.debug("Processing USB SUBMIT request", context: ["dataSize": data.count])
        
        // Decode the SUBMIT request
        let request = try USBIPMessageDecoder.decodeUSBSubmitRequest(from: data)
        
        logger.info("Processing SUBMIT request", context: [
            "seqnum": String(request.seqnum),
            "devid": String(request.devid),
            "direction": String(request.direction),
            "endpoint": String(format: "0x%02x", request.ep)
        ])
        
        // Validate request parameters
        try validateSubmitRequest(request)
        
        // Check concurrent request limit
        try await checkConcurrentRequestLimit()
        
        // Create URB for tracking
        let urb = USBRequestBlock(
            seqnum: request.seqnum,
            devid: request.devid,
            direction: request.direction == 1 ? .in : .out,
            endpoint: UInt8(request.ep & 0xFF),
            transferType: try inferTransferType(from: request),
            transferFlags: request.transferFlags,
            bufferLength: request.transferBufferLength,
            setupPacket: request.setup.isEmpty ? nil : request.setup,
            transferBuffer: request.transferBuffer,
            timeout: 5000,
            startFrame: request.startFrame,
            numberOfPackets: request.numberOfPackets,
            interval: request.interval
        )
        
        // Track the URB
        try await addActiveURB(urb)
        
        do {
            // Execute the USB transfer
            let result = try await executeUSBTransfer(request: request, urb: urb)
            
            // Create and return response
            let response = createSubmitResponse(from: request, result: result)
            
            logger.info("SUBMIT request completed successfully", context: [
                "seqnum": String(request.seqnum),
                "actualLength": String(result.actualLength),
                "status": String(result.status.rawValue)
            ])
            
            // Remove URB from tracking
            await removeActiveURB(request.seqnum)
            
            return try USBIPMessageEncoder.encodeUSBSubmitResponse(
                seqnum: response.seqnum,
                devid: response.devid,
                direction: response.direction,
                ep: response.ep,
                status: response.status,
                actualLength: response.actualLength,
                startFrame: response.startFrame,
                numberOfPackets: response.numberOfPackets,
                errorCount: response.errorCount,
                transferBuffer: response.transferBuffer
            )
            
        } catch {
            logger.error("SUBMIT request failed", context: [
                "seqnum": String(request.seqnum),
                "error": error.localizedDescription
            ])
            
            // Create error response
            let errorResponse = createErrorResponse(from: request, error: error)
            
            // Remove URB from tracking
            await removeActiveURB(request.seqnum)
            
            return try USBIPMessageEncoder.encodeUSBSubmitResponse(
                seqnum: errorResponse.seqnum,
                devid: errorResponse.devid,
                direction: errorResponse.direction,
                ep: errorResponse.ep,
                status: errorResponse.status,
                actualLength: errorResponse.actualLength,
                transferBuffer: errorResponse.transferBuffer
            )
        }
    }
    
    /// Validate SUBMIT request parameters
    private func validateSubmitRequest(_ request: USBIPSubmitRequest) throws {
        // Validate endpoint address
        guard request.ep <= 0xFF else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        // Validate direction
        guard request.direction <= 1 else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        // Validate transfer buffer length for OUT transfers
        if request.direction == 0 { // OUT
            if let buffer = request.transferBuffer {
                guard buffer.count <= request.transferBufferLength else {
                    throw USBIPProtocolError.invalidDataLength
                }
            }
        }
        
        // Validate setup packet size for control transfers
        if request.ep & 0x7F == 0 { // Control endpoint
            guard request.setup.count == 8 else {
                throw USBIPProtocolError.invalidMessageFormat
            }
        }
    }
    
    /// Check concurrent request limit
    private func checkConcurrentRequestLimit() async throws {
        let activeCount = await urbQueue.sync { activeURBs.count }
        
        guard activeCount < maxConcurrentRequests else {
            logger.warning("Concurrent request limit reached", context: [
                "activeRequests": String(activeCount),
                "maxRequests": String(maxConcurrentRequests)
            ])
            throw USBRequestError.tooManyRequests
        }
    }
    
    /// Add URB to active tracking
    private func addActiveURB(_ urb: USBRequestBlock) async throws {
        try await urbQueue.sync {
            guard activeURBs[urb.seqnum] == nil else {
                throw USBRequestError.duplicateRequest
            }
            activeURBs[urb.seqnum] = (urb: urb, status: .pending)
        }
    }
    
    /// Remove URB from active tracking
    private func removeActiveURB(_ seqnum: UInt32) async {
        await urbQueue.sync {
            activeURBs.removeValue(forKey: seqnum)
        }
    }
    
    /// Update URB status
    private func updateURBStatus(_ seqnum: UInt32, status: URBStatus) async {
        await urbQueue.sync {
            if var entry = activeURBs[seqnum] {
                entry.status = status
                activeURBs[seqnum] = entry
            }
        }
    }
    
    /// Execute USB transfer through device communicator
    private func executeUSBTransfer(request: USBIPSubmitRequest, urb: USBRequestBlock) async throws -> USBTransferResult {
        guard let communicator = deviceCommunicator else {
            throw USBRequestError.deviceNotAvailable
        }
        
        // Update URB status
        await updateURBStatus(urb.seqnum, status: .inProgress)
        
        // Execute based on transfer type
        switch urb.transferType {
        case .control:
            return try await executeControlTransfer(request: request, urb: urb, communicator: communicator)
        case .bulk:
            return try await executeBulkTransfer(request: request, urb: urb, communicator: communicator)
        case .interrupt:
            return try await executeInterruptTransfer(request: request, urb: urb, communicator: communicator)
        case .isochronous:
            return try await executeIsochronousTransfer(request: request, urb: urb, communicator: communicator)
        }
    }
    
    /// Execute control transfer
    private func executeControlTransfer(request: USBIPSubmitRequest, urb: USBRequestBlock, communicator: USBDeviceCommunicatorProtocol) async throws -> USBTransferResult {
        let deviceID = String(request.devid)
        
        if urb.direction == .out {
            return try await communicator.performControlTransferOut(
                deviceID: deviceID,
                setup: urb.setupPacket ?? Data(count: 8),
                data: urb.transferBuffer ?? Data(),
                timeout: urb.timeout
            )
        } else {
            return try await communicator.performControlTransferIn(
                deviceID: deviceID,
                setup: urb.setupPacket ?? Data(count: 8),
                length: Int(urb.bufferLength),
                timeout: urb.timeout
            )
        }
    }
    
    /// Execute bulk transfer
    private func executeBulkTransfer(request: USBIPSubmitRequest, urb: USBRequestBlock, communicator: USBDeviceCommunicatorProtocol) async throws -> USBTransferResult {
        let deviceID = String(request.devid)
        
        if urb.direction == .out {
            return try await communicator.performBulkTransferOut(
                deviceID: deviceID,
                endpoint: urb.endpoint,
                data: urb.transferBuffer ?? Data(),
                timeout: urb.timeout
            )
        } else {
            return try await communicator.performBulkTransferIn(
                deviceID: deviceID,
                endpoint: urb.endpoint,
                length: Int(urb.bufferLength),
                timeout: urb.timeout
            )
        }
    }
    
    /// Execute interrupt transfer
    private func executeInterruptTransfer(request: USBIPSubmitRequest, urb: USBRequestBlock, communicator: USBDeviceCommunicatorProtocol) async throws -> USBTransferResult {
        let deviceID = String(request.devid)
        
        if urb.direction == .out {
            return try await communicator.performInterruptTransferOut(
                deviceID: deviceID,
                endpoint: urb.endpoint,
                data: urb.transferBuffer ?? Data(),
                timeout: urb.timeout
            )
        } else {
            return try await communicator.performInterruptTransferIn(
                deviceID: deviceID,
                endpoint: urb.endpoint,
                length: Int(urb.bufferLength),
                timeout: urb.timeout
            )
        }
    }
    
    /// Execute isochronous transfer
    private func executeIsochronousTransfer(request: USBIPSubmitRequest, urb: USBRequestBlock, communicator: USBDeviceCommunicatorProtocol) async throws -> USBTransferResult {
        let deviceID = String(request.devid)
        
        if urb.direction == .out {
            return try await communicator.performIsochronousTransferOut(
                deviceID: deviceID,
                endpoint: urb.endpoint,
                data: urb.transferBuffer ?? Data(),
                startFrame: urb.startFrame,
                numberOfPackets: Int(urb.numberOfPackets),
                timeout: urb.timeout
            )
        } else {
            return try await communicator.performIsochronousTransferIn(
                deviceID: deviceID,
                endpoint: urb.endpoint,
                length: Int(urb.bufferLength),
                startFrame: urb.startFrame,
                numberOfPackets: Int(urb.numberOfPackets),
                timeout: urb.timeout
            )
        }
    }
    
    /// Infer transfer type from request
    private func inferTransferType(from request: USBIPSubmitRequest) throws -> USBTransferType {
        // Control transfers are on endpoint 0
        if (request.ep & 0x7F) == 0 {
            return .control
        }
        
        // For other endpoints, we need to determine transfer type
        // This is a simplified implementation - in practice, we would
        // query the device descriptor to determine the actual transfer type
        
        // Check for isochronous transfers (has numberOfPackets > 0)
        if request.numberOfPackets > 0 {
            return .isochronous
        }
        
        // Default to bulk for data endpoints
        return .bulk
    }
    
    /// Create successful SUBMIT response
    private func createSubmitResponse(from request: USBIPSubmitRequest, result: USBTransferResult) -> USBIPSubmitResponse {
        return USBIPSubmitResponse(
            seqnum: request.seqnum,
            devid: request.devid,
            direction: request.direction,
            ep: request.ep,
            status: Int32(result.status.rawValue),
            actualLength: UInt32(result.actualLength),
            startFrame: request.startFrame,
            numberOfPackets: request.numberOfPackets,
            errorCount: UInt32(result.errorCount),
            transferBuffer: result.data
        )
    }
    
    /// Create error SUBMIT response
    private func createErrorResponse(from request: USBIPSubmitRequest, error: Error) -> USBIPSubmitResponse {
        let status: Int32
        
        if let usbError = error as? USBRequestError {
            switch usbError {
            case .timeout:
                status = -110 // ETIMEDOUT
            case .deviceNotAvailable:
                status = -19 // ENODEV
            case .invalidParameters:
                status = -22 // EINVAL
            case .tooManyRequests:
                status = -11 // EAGAIN
            case .duplicateRequest:
                status = -17 // EEXIST
            case .cancelled:
                status = -2 // ENOENT (cancelled)
            }
        } else {
            status = -71 // EPROTO (generic protocol error)
        }
        
        return USBIPSubmitResponse(
            seqnum: request.seqnum,
            devid: request.devid,
            direction: request.direction,
            ep: request.ep,
            status: status,
            actualLength: 0,
            startFrame: request.startFrame,
            numberOfPackets: request.numberOfPackets,
            errorCount: 0,
            transferBuffer: nil
        )
    }
    
    /// Get active URB count for monitoring
    public func getActiveURBCount() async -> Int {
        return await urbQueue.sync { activeURBs.count }
    }
    
    /// Cancel URB by sequence number (for UNLINK support)
    public func cancelURB(_ seqnum: UInt32) async -> Bool {
        return await urbQueue.sync {
            guard var entry = activeURBs[seqnum] else {
                return false
            }
            entry.status = .cancelled
            activeURBs[seqnum] = entry
            return true
        }
    }
}

/// Protocol for USB device communication
public protocol USBDeviceCommunicatorProtocol: AnyObject {
    /// Control transfer operations
    func performControlTransferOut(deviceID: String, setup: Data, data: Data, timeout: UInt32) async throws -> USBTransferResult
    func performControlTransferIn(deviceID: String, setup: Data, length: Int, timeout: UInt32) async throws -> USBTransferResult
    
    /// Bulk transfer operations  
    func performBulkTransferOut(deviceID: String, endpoint: UInt8, data: Data, timeout: UInt32) async throws -> USBTransferResult
    func performBulkTransferIn(deviceID: String, endpoint: UInt8, length: Int, timeout: UInt32) async throws -> USBTransferResult
    
    /// Interrupt transfer operations
    func performInterruptTransferOut(deviceID: String, endpoint: UInt8, data: Data, timeout: UInt32) async throws -> USBTransferResult
    func performInterruptTransferIn(deviceID: String, endpoint: UInt8, length: Int, timeout: UInt32) async throws -> USBTransferResult
    
    /// Isochronous transfer operations
    func performIsochronousTransferOut(deviceID: String, endpoint: UInt8, data: Data, startFrame: UInt32, numberOfPackets: Int, timeout: UInt32) async throws -> USBTransferResult
    func performIsochronousTransferIn(deviceID: String, endpoint: UInt8, length: Int, startFrame: UInt32, numberOfPackets: Int, timeout: UInt32) async throws -> USBTransferResult
}