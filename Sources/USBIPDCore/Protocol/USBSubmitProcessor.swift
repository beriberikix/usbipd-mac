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
    private weak var deviceCommunicator: USBDeviceCommunicator?

    /// Used to resolve a devid back to the real device. Without it the processor can
    /// only fabricate a placeholder, which no IOKit lookup can match.
    private var deviceDiscovery: DeviceDiscovery?
    
    /// Logger for error and diagnostic information
    private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "usb-submit-processor")
    
    /// Limits applied to client-supplied request parameters. These were configurable
    /// and unread: the caps below were hardcoded here while ServerConfig persisted its
    /// own values that nothing consulted. Defaults match the previous constants, so
    /// behaviour is unchanged for anyone who never set them.
    private let config: ServerConfig?

    /// Maximum concurrent USB requests across all devices
    private var maxConcurrentRequests: Int { config?.maxTotalConcurrentRequests ?? 64 }

    /// Maximum in-flight URBs for any single device
    private var maxPendingURBsPerDevice: Int { config?.maxPendingURBsPerDevice ?? 32 }

    /// Largest transfer buffer a client may ask for
    private var maxUSBBufferSize: UInt32 { config?.maxUSBBufferSize ?? 1_048_576 }

    /// Per-operation USB timeout in milliseconds
    private var usbOperationTimeout: UInt32 { config?.usbOperationTimeout ?? 5000 }

    /// Initialize with device communicator
    public init(deviceCommunicator: USBDeviceCommunicator? = nil,
                deviceDiscovery: DeviceDiscovery? = nil,
                config: ServerConfig? = nil) {
        self.deviceCommunicator = deviceCommunicator
        self.deviceDiscovery = deviceDiscovery
        self.config = config
    }
    
    /// Set the device communicator
    public func setDeviceCommunicator(_ communicator: USBDeviceCommunicator) {
        self.deviceCommunicator = communicator
        logger.info("USBSubmitProcessor configured with production device communicator")
    }

    /// Provide device discovery so submitted URBs can be matched to a real device.
    public func setDeviceDiscovery(_ discovery: DeviceDiscovery) {
        self.deviceDiscovery = discovery
        logger.info("USBSubmitProcessor configured with device discovery")
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
        
        // Answer rejected requests with a RET_SUBMIT carrying the error, rather than
        // throwing. A thrown error reaches ServerCoordinator, which logs it and sends
        // nothing, leaving the client waiting on a reply that never comes.
        do {
            try validateSubmitRequest(request)
            try await checkConcurrentRequestLimit(devid: request.devid)
        } catch {
            logger.warning("Rejected SUBMIT request", context: [
                "seqnum": String(request.seqnum),
                "error": error.localizedDescription
            ])
            let errorResponse = createErrorResponse(from: request, error: error)
            return try USBIPMessageEncoder.encodeUSBSubmitResponse(
                seqnum: errorResponse.seqnum,
                devid: errorResponse.devid,
                direction: errorResponse.direction,
                ep: errorResponse.ep,
                status: errorResponse.status,
                actualLength: errorResponse.actualLength,
                startFrame: errorResponse.startFrame,
                numberOfPackets: errorResponse.numberOfPackets,
                errorCount: errorResponse.errorCount,
                transferBuffer: errorResponse.transferBuffer
            )
        }
        
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
            timeout: usbOperationTimeout,
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
        
        // Bound the requested transfer size. IOKitUSBInterface allocates
        // Int(bufferLength) directly from this value, so an unbounded UInt32 from the
        // wire becomes an allocation of up to 4 GiB requested by a remote client.
        guard request.transferBufferLength <= maxUSBBufferSize else {
            logger.warning("Rejected oversized transfer", context: [
                "requested": String(request.transferBufferLength),
                "maximum": String(maxUSBBufferSize)
            ])
            throw USBRequestError.invalidParameters
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
    private func checkConcurrentRequestLimit(devid: UInt32) async throws {
        let (activeCount, deviceCount) = urbQueue.sync {
            (activeURBs.count, activeURBs.values.filter { $0.urb.devid == devid }.count)
        }

        guard activeCount < maxConcurrentRequests else {
            logger.warning("Concurrent request limit reached", context: [
                "activeRequests": String(activeCount),
                "maxRequests": String(maxConcurrentRequests)
            ])
            throw USBRequestError.tooManyRequests
        }

        // Without a per-device cap one busy device can consume the whole global
        // budget and starve every other bound device.
        guard deviceCount < maxPendingURBsPerDevice else {
            logger.warning("Per-device URB limit reached", context: [
                "devid": String(devid),
                "devicePending": String(deviceCount),
                "maxPerDevice": String(maxPendingURBsPerDevice)
            ])
            throw USBRequestError.tooManyRequests
        }
    }
    
    /// Add URB to active tracking
    private func addActiveURB(_ urb: USBRequestBlock) async throws {
        // Barrier: this mutates shared state on a concurrent queue. Plain .sync
        // lets writers run simultaneously and corrupts the dictionary.
        try urbQueue.sync(flags: .barrier) {
            guard activeURBs[urb.seqnum] == nil else {
                throw USBRequestError.duplicateRequest
            }
            activeURBs[urb.seqnum] = (urb: urb, status: .pending)
        }
    }
    
    /// Remove URB from active tracking
    private func removeActiveURB(_ seqnum: UInt32) async {
        // Barrier: this mutates shared state on a concurrent queue. Plain .sync
        // lets writers run simultaneously and corrupts the dictionary.
        _ = urbQueue.sync(flags: .barrier) {
            activeURBs.removeValue(forKey: seqnum)
        }
    }
    
    /// Update URB status
    private func updateURBStatus(_ seqnum: UInt32, status: URBStatus) async {
        // Barrier: this mutates shared state on a concurrent queue. Plain .sync
        // lets writers run simultaneously and corrupts the dictionary.
        urbQueue.sync(flags: .barrier) {
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
    private func executeControlTransfer(request: USBIPSubmitRequest, urb: USBRequestBlock, communicator: USBDeviceCommunicator) async throws -> USBTransferResult {
        let device = try createUSBDeviceFromRequest(request)
        
        // Ensure USB interface is open for transfer execution
        let interfaceNumber: UInt8 = 0 // Control transfers typically use interface 0
        if !communicator.isInterfaceOpen(device: device, interfaceNumber: interfaceNumber) {
            try await communicator.openUSBInterface(device: device, interfaceNumber: interfaceNumber)
        }
        
        return try await communicator.executeControlTransfer(
            device: device,
            request: urb
        )
    }
    
    /// Execute bulk transfer
    private func executeBulkTransfer(request: USBIPSubmitRequest, urb: USBRequestBlock, communicator: USBDeviceCommunicator) async throws -> USBTransferResult {
        let device = try createUSBDeviceFromRequest(request)
        
        // Ensure USB interface is open for transfer execution
        let interfaceNumber: UInt8 = 0 // Default interface, would ideally be derived from endpoint
        if !communicator.isInterfaceOpen(device: device, interfaceNumber: interfaceNumber) {
            try await communicator.openUSBInterface(device: device, interfaceNumber: interfaceNumber)
        }
        
        return try await communicator.executeBulkTransfer(
            device: device,
            request: urb
        )
    }
    
    /// Execute interrupt transfer
    private func executeInterruptTransfer(request: USBIPSubmitRequest, urb: USBRequestBlock, communicator: USBDeviceCommunicator) async throws -> USBTransferResult {
        let device = try createUSBDeviceFromRequest(request)
        
        // Ensure USB interface is open for transfer execution
        let interfaceNumber: UInt8 = 0 // Default interface, would ideally be derived from endpoint
        if !communicator.isInterfaceOpen(device: device, interfaceNumber: interfaceNumber) {
            try await communicator.openUSBInterface(device: device, interfaceNumber: interfaceNumber)
        }
        
        return try await communicator.executeInterruptTransfer(
            device: device,
            request: urb
        )
    }
    
    /// Execute isochronous transfer
    private func executeIsochronousTransfer(request: USBIPSubmitRequest, urb: USBRequestBlock, communicator: USBDeviceCommunicator) async throws -> USBTransferResult {
        let device = try createUSBDeviceFromRequest(request)
        
        // Ensure USB interface is open for transfer execution
        let interfaceNumber: UInt8 = 0 // Default interface, would ideally be derived from endpoint
        if !communicator.isInterfaceOpen(device: device, interfaceNumber: interfaceNumber) {
            try await communicator.openUSBInterface(device: device, interfaceNumber: interfaceNumber)
        }
        
        return try await communicator.executeIsochronousTransfer(
            device: device,
            request: urb
        )
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
        
        // Isochronous transfers carry a packet count.
        if request.numberOfPackets > 0 {
            return .isochronous
        }

        // A non-zero polling interval on a data endpoint means interrupt. Bulk
        // transfers leave interval at 0, and the isochronous case is already handled
        // above, so this is unambiguous for the fields CMD_SUBMIT actually carries.
        //
        // Without this every interrupt endpoint was driven as bulk, since the branch
        // below was the only remaining outcome.
        if request.interval > 0 {
            return .interrupt
        }

        // Default to bulk for data endpoints.
        //
        // The authoritative source is the endpoint descriptor's bmAttributes, which
        // this layer does not consult; it infers from the request alone. Endpoints
        // configured as interrupt but submitted with interval 0 will still be treated
        // as bulk.
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
            case .requestFailed:
                status = -71 // EPROTO (generic protocol error)
            case .invalidURB:
                status = -22 // EINVAL
            case .deviceNotClaimed:
                status = -19 // ENODEV
            case .endpointNotFound:
                status = -22 // EINVAL
            case .transferTypeNotSupported:
                status = -95 // EOPNOTSUPP
            case .bufferSizeMismatch:
                status = -22 // EINVAL
            case .setupPacketRequired:
                status = -22 // EINVAL
            case .setupPacketInvalid:
                status = -22 // EINVAL
            case .timeoutInvalid:
                status = -22 // EINVAL
            case .concurrentRequestLimit:
                status = -11 // EAGAIN
            case .requestCancelled:
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
        return urbQueue.sync { activeURBs.count }
    }
    
    /// Cancel URB by sequence number (for UNLINK support)
    public func cancelURB(_ seqnum: UInt32) async -> Bool {
        // Barrier: this mutates shared state on a concurrent queue. Plain .sync
        // lets writers run simultaneously and corrupts the dictionary.
        return urbQueue.sync(flags: .barrier) {
            guard var entry = activeURBs[seqnum] else {
                return false
            }
            entry.status = .cancelled
            activeURBs[seqnum] = entry
            return true
        }
    }
    
    /// Create a USBDevice object from USB/IP request information
    /// Uses device discovery to get actual device information instead of placeholders
    private func createUSBDeviceFromRequest(_ request: USBIPSubmitRequest) throws -> USBDevice {
        // USB/IP encodes devid as (busnum << 16) | devnum.
        let busID = String((request.devid >> 16) & 0xFF)
        let deviceID = String(request.devid & 0xFFFF)

        // Resolve the real device. This used to fabricate one with vendorID and
        // productID of 0x0000 and speed .unknown, deferring to "full implementation".
        // IOKitUSBInterface locates a device by vendor and product ID, so a
        // placeholder matched nothing and every transfer came back ENODEV — a
        // correctly framed RET_SUBMIT reporting that the device did not exist.
        guard let discovery = deviceDiscovery else {
            throw USBRequestError.deviceNotAvailable
        }

        guard let device = try discovery.getDevice(busID: busID, deviceID: deviceID) else {
            throw USBRequestError.deviceNotAvailable
        }

        return device
    }
}