// USBSubmitProcessor.swift
// Processes USB/IP SUBMIT requests and coordinates USB transfer execution

import Foundation
import Common

/// Processor for USB/IP SUBMIT requests with URB lifecycle management
public class USBSubmitProcessor {
    /// Active USB Request Blocks (URBs) tracking with status
    /// One request in flight.
    ///
    /// The device is kept beside the URB so a cancel can abort the right pipe without
    /// re-enumerating IOKit, and without the caller having to know which device a
    /// sequence number belongs to.
    private struct TrackedURB {
        let urb: USBRequestBlock
        var status: URBStatus
        let device: USBDevice?
    }

    /// What a cancel found, read out under the lock and acted on outside it.
    private struct CancelClaim {
        let reserved: Bool
        let urb: USBRequestBlock?
        let device: USBDevice?
        /// Set when the request had already completed and its reply is being sent.
        var replyInFlight: DispatchSemaphore?
    }

    /// Identifies a request. A sequence number alone does not.
    ///
    /// USB/IP numbers requests per connection, and the Linux client opens one connection
    /// per attached device, so every client starts again at 1. Tracking by bare sequence
    /// number put all of them in one namespace: a second client's first request looked
    /// like a duplicate of the first client's, and attaching two devices from a single
    /// machine was enough to trigger it. Devid distinguishes them, since a connection
    /// carries exactly one imported device.
    private struct URBKey: Hashable {
        let devid: UInt32
        let seqnum: UInt32
    }

    private var activeURBs: [URBKey: TrackedURB] = [:]

    /// Requests accepted and not yet answered, claimed before the URB exists so that an
    /// UNLINK arriving during setup has something to find.
    private var reserved: Set<URBKey> = []

    /// Requests the client withdrew. A transfer already in IOKit's hands may still
    /// complete after the abort, and its result must be dropped rather than sent: the
    /// client has been told the request is dead and is not expecting a reply.
    private var cancelled: Set<URBKey> = []

    /// Replies claimed for sending and not yet on the socket, each with a signal raised
    /// once it is. See `claimReply` and `cancelURB`.
    private var repliesInFlight: [URBKey: DispatchSemaphore] = [:]

    /// Requests off the wire and waiting on their lane, not yet started. An UNLINK that
    /// finds one here cancels it outright; it is dropped when its turn comes.
    private var queued: Set<URBKey> = []

    /// Devices already resolved from a devid. Resolving means a full IOKit enumeration,
    /// and it ran twice for every URB: about 2 ms of a CMSIS-DAP command's round trip,
    /// enough that openocd took longer than gdb's 2-second timeout to answer an attach.
    ///
    /// Also what pins a client to the device it imported. It is kept when the device
    /// goes away and cleared only when a client leaves (forgetResolvedDevices): a
    /// different device appearing at the same location then fails the identity check
    /// in IOKitUSBDevice rather than silently taking the old one's place. Clearing it on
    /// failure let exactly that happen — a probe rebooted into BOOTSEL was served on the
    /// connection that had imported the probe, the client's cancels went to a device
    /// that had never seen the transfers, and its vhci port wedged.
    ///
    /// Guarded by `urbQueue`.
    private var resolvedDevices: [UInt32: USBDevice] = [:]
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
    private var usbOperationTimeout: UInt32 { config?.usbOperationTimeout ?? 60000 }

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
        
        // Debug, not info: a debug probe issues thousands of these a second, and at info
        // they grew the daemon's log by hundreds of megabytes and cost time on every URB.
        logger.debug("Processing SUBMIT request", context: [
            "seqnum": String(request.seqnum),
            "devid": String(request.devid),
            "direction": String(request.direction),
            "endpoint": String(format: "0x%02x", request.ep)
        ])
        
        // Answer rejected requests with a RET_SUBMIT carrying the error, rather than
        // throwing. A thrown error reaches ServerCoordinator, which logs it and sends
        // nothing, leaving the client waiting on a reply that never comes.
        do {
            // Claim the request before doing anything that can block.
            //
            // Registration used to happen after the device had been resolved, which
            // means after an IOKit enumeration. A client that submits a read and cancels
            // it a millisecond later — probe-rs drains the IN endpoint exactly that way
            // before its first command — sent the UNLINK into that window, found no such
            // URB, and was told the request had already completed. It had not: it went
            // on to run, and later returned data for a request the client had abandoned.
            //
            // This sits inside the block above so that a rejected claim is answered.
            // Thrown from outside it, a duplicate reached ServerCoordinator, which logs
            // and sends nothing, and the client waited for a reply that never came.
            guard try reserveSequenceNumber(devid: request.devid, seqnum: request.seqnum) else {
                logger.debug("Dropping a request cancelled before it ran", context: [
                    "seqnum": String(request.seqnum)
                ])
                return Data()
            }

            // Checked after the claim, so a rejection is answered through claimReply
            // like any other reply and an UNLINK cannot overtake it.
            do {
                try validateSubmitRequest(request)
                try await checkConcurrentRequestLimit(devid: request.devid)
            } catch {
                guard claimReply(devid: request.devid, seqnum: request.seqnum) else { return Data() }
                throw error
            }
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
        
        // Prefer the device's own description of the endpoint. CMD_SUBMIT has no
        // transfer-type field, so anything derived from the request alone is a guess —
        // and the interval-based guess below misreads every bulk endpoint that
        // declares a non-zero bInterval, which is common.
        let device = try? createUSBDeviceFromRequest(request)
        let endpointAddress = UInt8(request.ep & 0xFF)
        let reportedType = device.flatMap { resolved in
            deviceCommunicator?.endpointTransferType(
                device: resolved,
                endpoint: request.direction == 1 ? (endpointAddress | 0x80) : endpointAddress
            )
        }

        // Create URB for tracking
        let urb = USBRequestBlock(
            seqnum: request.seqnum,
            devid: request.devid,
            direction: request.direction == 1 ? .in : .out,
            endpoint: UInt8(request.ep & 0xFF),
            transferType: try reportedType ?? inferTransferType(from: request),
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
        try await addActiveURB(urb, device: device)
        
        do {
            // Execute the USB transfer
            let result = try await executeUSBTransfer(request: request, urb: urb)

            // Create and return response
            let response = createSubmitResponse(from: request, result: result)
            
            logger.debug("SUBMIT request completed successfully", context: [
                "seqnum": String(request.seqnum),
                "actualLength": String(result.actualLength),
                "status": String(result.status.rawValue)
            ])
            
            // A withdrawn request gets no RET_SUBMIT. The client was answered by the
            // RET_UNLINK and has freed the sequence number; a late reply for it is an
            // unexpected message that leaves the two sides disagreeing about what is
            // outstanding. Linux's own server behaves the same way — a successfully
            // unlinked URB completes with RET_UNLINK and nothing else.
            //
            // The data is dropped with it. That is the honest outcome: it belongs to a
            // transfer the client cancelled, and handing it to the next read would put
            // one command's answer in front of another's.
            guard claimReply(devid: request.devid, seqnum: request.seqnum) else {
                logger.info("Discarding result of a cancelled request", context: [
                    "seqnum": String(request.seqnum),
                    "actualLength": String(result.actualLength)
                ])
                return Data()
            }

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
            // Aborting a pipe makes the transfer in flight fail, so a cancelled request
            // usually arrives here rather than above. It is silent for the same reason.
            guard claimReply(devid: request.devid, seqnum: request.seqnum) else {
                logger.info("Cancelled request ended without a reply", context: [
                    "seqnum": String(request.seqnum)
                ])
                return Data()
            }

            logger.error("SUBMIT request failed", context: [
                "seqnum": String(request.seqnum),
                "error": error.localizedDescription
            ])
            
            // Create error response
            let errorResponse = createErrorResponse(from: request, error: error)
            
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
        
        // Bound the requested transfer size. IOKitUSBDevice allocates
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
    
    /// Claim a sequence number before the URB itself can be built.
    ///
    /// This is what makes an UNLINK that arrives during setup meaningful. It also
    /// carries the duplicate check that used to live in `addActiveURB`, which is the
    /// right place for it: a repeat of a sequence number is a client error whether or
    /// not the first one has finished being prepared.
    ///
    /// Returns false for a request its client cancelled while it was still queued.
    private func reserveSequenceNumber(devid: UInt32, seqnum: UInt32) throws -> Bool {
        return try urbQueue.sync(flags: .barrier) {
            let key = URBKey(devid: devid, seqnum: seqnum)
            if queued.remove(key) != nil, cancelled.remove(key) != nil {
                return false
            }
            guard !reserved.contains(key) else {
                throw USBRequestError.duplicateRequest
            }
            reserved.insert(key)
            return true
        }
    }

    /// Record a request as it comes off the wire, ahead of its turn on its lane.
    ///
    /// A lane runs one request at a time, and Linux's cdc_acm keeps sixteen reads posted
    /// on a serial port's IN endpoint, so fifteen of them wait while the first blocks.
    /// Closing the port unlinks all sixteen. The waiting ones were unknown here, so each
    /// UNLINK was answered "already completed" — and then the request ran and answered
    /// too, which the Linux client treats as a protocol violation and drops the
    /// connection over.
    public func requestReceived(devid: UInt32, seqnum: UInt32) {
        urbQueue.sync(flags: .barrier) {
            _ = queued.insert(URBKey(devid: devid, seqnum: seqnum))
        }
    }

    /// Add URB to active tracking
    private func addActiveURB(_ urb: USBRequestBlock, device: USBDevice?) async throws {
        // Barrier: this mutates shared state on a concurrent queue. Plain .sync
        // lets writers run simultaneously and corrupts the dictionary.
        urbQueue.sync(flags: .barrier) {
            activeURBs[URBKey(devid: urb.devid, seqnum: urb.seqnum)] =
                TrackedURB(urb: urb, status: .pending, device: device)
        }
    }

    /// Forget the device resolved at one location. Called when its client leaves, since
    /// the next device there may not be the one that was. Other clients stay pinned.
    public func forgetResolvedDevice(busID: String, deviceID: String) {
        urbQueue.sync(flags: .barrier) {
            resolvedDevices = resolvedDevices.filter { $0.value.busID != busID || $0.value.deviceID != deviceID }
        }
    }

    /// Whether the client withdrew this request while it was running.
    func wasCancelled(devid: UInt32, seqnum: UInt32) async -> Bool {
        return urbQueue.sync { cancelled.contains(URBKey(devid: devid, seqnum: seqnum)) }
    }

    /// Decide, once and atomically, whether a finished request is answered.
    ///
    /// Returns false if the client withdrew it first; its RET_UNLINK is the only answer.
    /// Otherwise the request stops being cancellable here, and its reply is marked in
    /// flight until `replySent` reports it written.
    ///
    /// This was a check followed by a removal, with the send later still. An UNLINK
    /// landing between the check and the send was acknowledged on its own lane and could
    /// reach the socket first — and the Linux client, having given the URB back on the
    /// RET_UNLINK, treats the RET_SUBMIT that follows as a protocol violation and drops
    /// the whole connection ("cannot find a urb of seqnum"). openocd hit it at exit,
    /// where it cancels reads that are completing at that same moment.
    func claimReply(devid: UInt32, seqnum: UInt32) -> Bool {
        return urbQueue.sync(flags: .barrier) {
            let key = URBKey(devid: devid, seqnum: seqnum)
            let wasCancelled = cancelled.contains(key)
            activeURBs.removeValue(forKey: key)
            reserved.remove(key)
            cancelled.remove(key)
            if !wasCancelled {
                repliesInFlight[key] = DispatchSemaphore(value: 0)
            }
            return !wasCancelled
        }
    }

    /// The reply claimed by `claimReply` has been written, or will never be. Releases any
    /// UNLINK waiting to be answered behind it.
    public func replySent(devid: UInt32, seqnum: UInt32) {
        let signal: DispatchSemaphore? = urbQueue.sync(flags: .barrier) {
            repliesInFlight.removeValue(forKey: URBKey(devid: devid, seqnum: seqnum))
        }
        signal?.signal()
    }

    /// Remove URB from active tracking
    private func removeActiveURB(devid: UInt32, seqnum: UInt32) async {
        // Barrier: this mutates shared state on a concurrent queue. Plain .sync
        // lets writers run simultaneously and corrupts the dictionary.
        urbQueue.sync(flags: .barrier) {
            let key = URBKey(devid: devid, seqnum: seqnum)
            activeURBs.removeValue(forKey: key)
            reserved.remove(key)
            cancelled.remove(key)
        }
    }
    
    /// Update URB status
    private func updateURBStatus(devid: UInt32, seqnum: UInt32, status: URBStatus) async {
        // Barrier: this mutates shared state on a concurrent queue. Plain .sync
        // lets writers run simultaneously and corrupts the dictionary.
        urbQueue.sync(flags: .barrier) {
            let key = URBKey(devid: devid, seqnum: seqnum)
            if var entry = activeURBs[key] {
                entry.status = status
                activeURBs[key] = entry
            }
        }
    }
    
    /// Execute USB transfer through device communicator
    private func executeUSBTransfer(request: USBIPSubmitRequest, urb: USBRequestBlock) async throws -> USBTransferResult {
        guard let communicator = deviceCommunicator else {
            throw USBRequestError.deviceNotAvailable
        }
        
        // Update URB status
        await updateURBStatus(devid: urb.devid, seqnum: urb.seqnum, status: .inProgress)
        
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
        
        // Opens the whole device on first use; the number is not consulted. Which
        // interface a transfer needs is decided by its endpoint, inside the communicator.
        let interfaceNumber: UInt8 = 0
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
        
        // Opens the whole device on first use; see executeControlTransfer.
        let interfaceNumber: UInt8 = 0
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
        
        // Opens the whole device on first use; see executeControlTransfer.
        let interfaceNumber: UInt8 = 0
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
        
        // Opens the whole device on first use; see executeControlTransfer.
        let interfaceNumber: UInt8 = 0
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

        // Fallback only: reached when the device cannot be asked. A non-zero interval
        // does NOT mean interrupt — bulk endpoints commonly declare bInterval 1, and a
        // J-Link does on both of its bulk pipes — so this guess is wrong as often as
        // it is right. It exists so a device that refuses to describe itself still
        // gets a plausible route rather than no transfer at all.

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
    
    /// Cancel a request (for UNLINK support).
    ///
    /// Takes the devid as well as the sequence number: numbering restarts per
    /// connection, so a sequence number on its own could name another client's request.
    public func cancelURB(devid: UInt32, seqnum: UInt32) async -> Bool {
        // Barrier: this mutates shared state on a concurrent queue. Plain .sync
        // lets writers run simultaneously and corrupts the dictionary.
        let claimed: CancelClaim = urbQueue.sync(flags: .barrier) {
            // A reservation is enough. Requiring an entry in activeURBs meant a request
            // still being set up could not be cancelled, and the client was told its URB
            // had already completed when in fact it had not started.
            let key = URBKey(devid: devid, seqnum: seqnum)
            if queued.contains(key) {
                // Not started: cancelling it is simply never running it.
                cancelled.insert(key)
                return CancelClaim(reserved: true, urb: nil, device: nil)
            }
            guard reserved.contains(key) else {
                var missed = CancelClaim(reserved: false, urb: nil, device: nil)
                missed.replyInFlight = repliesInFlight[key]
                return missed
            }
            cancelled.insert(key)
            guard var entry = activeURBs[key] else {
                return CancelClaim(reserved: true, urb: nil, device: nil)
            }
            entry.status = .cancelled
            activeURBs[key] = entry
            return CancelClaim(reserved: true, urb: entry.urb, device: entry.device)
        }

        guard claimed.reserved else {
            // Too late to cancel, and the reply is on its way. The RET_UNLINK saying so
            // must not overtake it, so wait for it to be written. Bounded, because a
            // connection that dies mid-send never reports back.
            if let inFlight = claimed.replyInFlight {
                waitForReplyWritten(inFlight)
            }
            return false
        }

        // Marking the URB is not enough on its own: the transfer is sitting inside a
        // blocking IOKit call and will run to completion, or to its timeout, unless the
        // pipe is aborted. Left running it collects whatever the device says next —
        // which is the answer to some later command — and that answer is then thrown
        // away with the cancelled request. probe-rs saw exactly this: every response it
        // wanted was consumed by a read it had already withdrawn.
        if let urb = claimed.urb, let device = claimed.device {
            await abortTransfer(for: urb, on: device)
        }
        return true
    }

    /// Synchronous on purpose: the wait is short and bounded, and UNLINKs run on their
    /// own lane, so blocking it holds up nothing but later UNLINKs.
    private func waitForReplyWritten(_ signal: DispatchSemaphore) {
        _ = signal.wait(timeout: .now() + .seconds(2))
    }

    /// Abort the pipe a cancelled URB is waiting on, so it returns immediately.
    ///
    /// The endpoint comes from the URB rather than from the UNLINK message. CMD_UNLINK
    /// carries ep 0 and direction 0 — the Linux client fills in neither, since the
    /// sequence number identifies the request on its own — so honouring those fields
    /// aborted the control pipe and left the real transfer running.
    private func abortTransfer(for urb: USBRequestBlock, on device: USBDevice) async {
        guard let communicator = deviceCommunicator else { return }

        let address = urb.direction == .in ? (urb.endpoint | 0x80) : urb.endpoint
        do {
            try await communicator.cancelTransfers(
                device: device,
                interfaceNumber: 0,
                endpoint: address
            )
        } catch {
            logger.warning("Could not abort a cancelled transfer", context: [
                "seqnum": String(urb.seqnum),
                "endpoint": String(format: "0x%02x", address),
                "error": error.localizedDescription
            ])
        }
    }
    
    /// Create a USBDevice object from USB/IP request information
    /// Uses device discovery to get actual device information instead of placeholders
    private func createUSBDeviceFromRequest(_ request: USBIPSubmitRequest) throws -> USBDevice {
        // Resolve the real device. This used to fabricate one with vendorID and
        // productID of 0x0000 and speed .unknown, deferring to "full implementation".
        // IOKitUSBDevice locates a device by location and identity, so a
        // placeholder matched nothing and every transfer came back ENODEV — a
        // correctly framed RET_SUBMIT reporting that the device did not exist.
        if let cached = urbQueue.sync(execute: { resolvedDevices[request.devid] }) {
            return cached
        }

        guard let discovery = deviceDiscovery else {
            throw USBRequestError.deviceNotAvailable
        }

        // Match the devid against the devices actually attached. Deriving a busid from
        // it arithmetically — busID from the high bits, deviceID from the low ones —
        // could not express a hub port path, so a device at 32-2.2 resolved to 32-2,
        // the hub above it, and every transfer was aimed at the wrong device.
        let devices = try discovery.discoverDevices()
        guard let device = USBIPDeviceIdentity.device(forDevid: request.devid, among: devices) else {
            throw USBRequestError.deviceNotAvailable
        }

        urbQueue.sync(flags: .barrier) { resolvedDevices[request.devid] = device }
        return device
    }
}