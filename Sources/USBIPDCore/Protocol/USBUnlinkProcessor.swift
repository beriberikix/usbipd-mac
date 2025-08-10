// USBUnlinkProcessor.swift
// Processes USB/IP UNLINK requests for cancelling USB operations

import Foundation
import Common

/// Processor for USB/IP UNLINK requests with URB cancellation capabilities
public class USBUnlinkProcessor {
    /// Reference to submit processor for URB cancellation
    private weak var submitProcessor: USBSubmitProcessor?
    
    /// Pending unlink requests tracking
    private var pendingUnlinks: [UInt32: USBIPUnlinkRequest] = [:]
    private let unlinkQueue = DispatchQueue(label: "com.usbipd.mac.unlink", attributes: .concurrent)
    
    /// Logger for error and diagnostic information
    private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "usb-unlink-processor")
    
    /// Initialize with submit processor reference
    public init(submitProcessor: USBSubmitProcessor? = nil) {
        self.submitProcessor = submitProcessor
    }
    
    /// Set the submit processor for URB cancellation
    public func setSubmitProcessor(_ processor: USBSubmitProcessor) {
        self.submitProcessor = processor
    }
    
    /// Process a USB UNLINK request and return response data
    public func processUnlinkRequest(_ data: Data) async throws -> Data {
        logger.debug("Processing USB UNLINK request", context: ["dataSize": data.count])
        
        // Decode the UNLINK request
        let request = try USBIPMessageDecoder.decodeUSBUnlinkRequest(from: data)
        
        logger.info("Processing UNLINK request", context: [
            "seqnum": String(request.seqnum),
            "devid": String(request.devid),
            "direction": String(request.direction),
            "endpoint": String(format: "0x%02x", request.ep),
            "unlinkSeqnum": String(request.unlinkSeqnum)
        ])
        
        // Validate request parameters
        try validateUnlinkRequest(request)
        
        // Track the unlink request
        await addPendingUnlinkRequest(request)
        
        do {
            // Attempt to cancel the specified URB
            let cancellationResult = await performURBCancellation(request)
            
            // Create and return response
            let response = createUnlinkResponse(from: request, success: cancellationResult.success)
            
            logger.info("UNLINK request processed", context: [
                "seqnum": String(request.seqnum),
                "unlinkSeqnum": String(request.unlinkSeqnum),
                "success": String(cancellationResult.success),
                "reason": cancellationResult.reason ?? "N/A"
            ])
            
            // Remove from tracking
            await removePendingUnlinkRequest(request.seqnum)
            
            return try USBIPMessageEncoder.encodeUSBUnlinkResponse(
                seqnum: response.seqnum,
                devid: response.devid,
                direction: response.direction,
                ep: response.ep,
                status: response.status
            )
            
        } catch {
            logger.error("UNLINK request failed", context: [
                "seqnum": String(request.seqnum),
                "unlinkSeqnum": String(request.unlinkSeqnum),
                "error": error.localizedDescription
            ])
            
            // Create error response
            let errorResponse = createErrorResponse(from: request, error: error)
            
            // Remove from tracking
            await removePendingUnlinkRequest(request.seqnum)
            
            return try USBIPMessageEncoder.encodeUSBUnlinkResponse(
                seqnum: errorResponse.seqnum,
                devid: errorResponse.devid,
                direction: errorResponse.direction,
                ep: errorResponse.ep,
                status: errorResponse.status
            )
        }
    }
    
    /// Validate UNLINK request parameters
    private func validateUnlinkRequest(_ request: USBIPUnlinkRequest) throws {
        // Validate endpoint address
        guard request.ep <= 0xFF else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        // Validate direction
        guard request.direction <= 1 else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        // Validate that we have a sequence number to unlink
        guard request.unlinkSeqnum != 0 else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        // Validate that we're not trying to unlink ourselves
        guard request.seqnum != request.unlinkSeqnum else {
            throw USBIPProtocolError.invalidMessageFormat
        }
    }
    
    /// Add unlink request to pending tracking
    private func addPendingUnlinkRequest(_ request: USBIPUnlinkRequest) async {
        await unlinkQueue.sync {
            pendingUnlinks[request.seqnum] = request
        }
    }
    
    /// Remove unlink request from pending tracking
    private func removePendingUnlinkRequest(_ seqnum: UInt32) async {
        await unlinkQueue.sync {
            pendingUnlinks.removeValue(forKey: seqnum)
        }
    }
    
    /// Perform URB cancellation
    private func performURBCancellation(_ request: USBIPUnlinkRequest) async -> (success: Bool, reason: String?) {
        guard let processor = submitProcessor else {
            logger.warning("Submit processor not available for URB cancellation")
            return (success: false, reason: "Submit processor not available")
        }
        
        // Check if the URB exists and can be cancelled
        let activeCount = await processor.getActiveURBCount()
        logger.debug("Attempting URB cancellation", context: [
            "unlinkSeqnum": String(request.unlinkSeqnum),
            "activeURBCount": String(activeCount)
        ])
        
        // Attempt to cancel the URB
        let success = await processor.cancelURB(request.unlinkSeqnum)
        
        if success {
            logger.debug("URB cancellation successful", context: [
                "unlinkSeqnum": String(request.unlinkSeqnum)
            ])
            return (success: true, reason: nil)
        } else {
            logger.debug("URB cancellation failed - URB not found or already completed", context: [
                "unlinkSeqnum": String(request.unlinkSeqnum)
            ])
            return (success: false, reason: "URB not found or already completed")
        }
    }
    
    /// Create successful UNLINK response
    private func createUnlinkResponse(from request: USBIPUnlinkRequest, success: Bool) -> USBIPUnlinkResponse {
        let status: Int32 = success ? 0 : -2 // 0 = success, -2 = ENOENT (not found)
        
        return USBIPUnlinkResponse(
            seqnum: request.seqnum,
            devid: request.devid,
            direction: request.direction,
            ep: request.ep,
            status: status
        )
    }
    
    /// Create error UNLINK response
    private func createErrorResponse(from request: USBIPUnlinkRequest, error: Error) -> USBIPUnlinkResponse {
        let status: Int32
        
        if let usbError = error as? USBRequestError {
            switch usbError {
            case .deviceNotAvailable:
                status = -19 // ENODEV
            case .invalidParameters:
                status = -22 // EINVAL
            case .cancelled:
                status = -2  // ENOENT
            default:
                status = -71 // EPROTO (generic protocol error)
            }
        } else if error is USBIPProtocolError {
            status = -22 // EINVAL (invalid message format)
        } else {
            status = -71 // EPROTO (generic protocol error)
        }
        
        return USBIPUnlinkResponse(
            seqnum: request.seqnum,
            devid: request.devid,
            direction: request.direction,
            ep: request.ep,
            status: status
        )
    }
    
    /// Get pending unlink count for monitoring
    public func getPendingUnlinkCount() async -> Int {
        return await unlinkQueue.sync { pendingUnlinks.count }
    }
    
    /// Check if a specific unlink request is pending
    public func isUnlinkRequestPending(_ seqnum: UInt32) async -> Bool {
        return await unlinkQueue.sync { pendingUnlinks[seqnum] != nil }
    }
    
    /// Cancel all pending unlink requests (for cleanup)
    public func cancelAllPendingUnlinks() async -> [USBIPUnlinkRequest] {
        return await unlinkQueue.sync {
            let pending = Array(pendingUnlinks.values)
            pendingUnlinks.removeAll()
            return pending
        }
    }
    
    /// Handle shutdown and cleanup
    public func shutdown() async {
        logger.info("USB UNLINK processor shutting down")
        
        let pendingCount = await getPendingUnlinkCount()
        if pendingCount > 0 {
            logger.warning("Shutting down with pending unlink requests", context: [
                "pendingCount": String(pendingCount)
            ])
            
            let cancelled = await cancelAllPendingUnlinks()
            logger.info("Cancelled pending unlink requests", context: [
                "cancelledCount": String(cancelled.count)
            ])
        }
    }
    
    /// Get statistics for monitoring
    public func getStatistics() async -> UnlinkProcessorStatistics {
        let pendingCount = await getPendingUnlinkCount()
        
        return UnlinkProcessorStatistics(
            pendingUnlinkRequests: pendingCount,
            hasSubmitProcessor: submitProcessor != nil
        )
    }
}

/// Statistics for UNLINK processor monitoring
public struct UnlinkProcessorStatistics {
    /// Number of pending unlink requests
    public let pendingUnlinkRequests: Int
    
    /// Whether submit processor is available for cancellation
    public let hasSubmitProcessor: Bool
    
    public init(pendingUnlinkRequests: Int, hasSubmitProcessor: Bool) {
        self.pendingUnlinkRequests = pendingUnlinkRequests
        self.hasSubmitProcessor = hasSubmitProcessor
    }
}

/// Helper for batch unlink operations (for advanced use cases)
public extension USBUnlinkProcessor {
    /// Process multiple unlink requests concurrently
    func processUnlinkRequests(_ dataArray: [Data]) async throws -> [Data] {
        logger.debug("Processing batch unlink requests", context: [
            "requestCount": String(dataArray.count)
        ])
        
        // Process all requests concurrently
        let results = await withTaskGroup(of: (Int, Result<Data, Error>).self, returning: [Data].self) { group in
            // Add tasks for each request
            for (index, data) in dataArray.enumerated() {
                group.addTask {
                    do {
                        let response = try await self.processUnlinkRequest(data)
                        return (index, .success(response))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            
            // Collect results in order
            var results = Array<Data?>(repeating: nil, count: dataArray.count)
            for await (index, result) in group {
                switch result {
                case .success(let data):
                    results[index] = data
                case .failure(let error):
                    self.logger.error("Batch unlink request failed", context: [
                        "index": String(index),
                        "error": error.localizedDescription
                    ])
                    // Create a generic error response for failed requests
                    results[index] = try? self.createGenericErrorResponse()
                }
            }
            
            return results.compactMap { $0 }
        }
        
        logger.debug("Batch unlink requests completed", context: [
            "requestCount": String(dataArray.count),
            "responseCount": String(results.count)
        ])
        
        return results
    }
    
    /// Create a generic error response for batch processing failures
    private func createGenericErrorResponse() throws -> Data {
        let response = USBIPUnlinkResponse(
            seqnum: 0,
            devid: 0,
            direction: 0,
            ep: 0,
            status: -71 // EPROTO
        )
        
        return try USBIPMessageEncoder.encodeUSBUnlinkResponse(
            seqnum: response.seqnum,
            devid: response.devid,
            direction: response.direction,
            ep: response.ep,
            status: response.status
        )
    }
}