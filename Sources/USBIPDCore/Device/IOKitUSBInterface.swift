// IOKitUSBInterface.swift
// IOKit USB interface wrapper with all transfer types

import Foundation
import IOKit
import IOKit.usb
import Common

// IOKit constants manually defined since macros are unavailable
fileprivate let kIOUSBDeviceUserClientTypeID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x9d, 0xc7, 0xb7, 0x80, 0x9e, 0xc0, 0x11, 0xd4,
    0xa5, 0x4f, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

fileprivate let kIOCFPlugInInterfaceID = CFUUIDGetConstantUUIDWithBytes(nil,
    0xc2, 0x44, 0xe8, 0x58, 0x10, 0x9c, 0x11, 0xd4,
    0x91, 0xd4, 0x00, 0x50, 0xe4, 0xc6, 0x42, 0x6f)

fileprivate let kIOUSBDeviceInterfaceID300 = CFUUIDGetConstantUUIDWithBytes(nil,
    0x39, 0x61, 0x04, 0xf7, 0x94, 0x3d, 0x48, 0x93,
    0x90, 0xf1, 0x69, 0xbd, 0x6c, 0xf5, 0xc2, 0xeb)

/// IOKit wrapper for USB interface communication
public class IOKitUSBInterface {
    
    // MARK: - Properties
    
    private let device: USBDevice
    private let interfaceNumber: UInt8
    private let logger: Logger
    
    /// IOKit USB device interface reference  
    private var deviceInterface: UnsafeMutablePointer<IOUSBDeviceInterface300>?
    
    /// IOKit USB interface references keyed by endpoint
    private var interfaceRefs: [UInt8: UnsafeMutablePointer<IOUSBInterfaceInterface300>] = [:]
    
    /// Track interface open state
    private var isOpen: Bool = false
    
    /// IOKit device reference for the USB device
    private var deviceRef: io_service_t = 0
    
    /// IOKit interface wrapper for testing
    private let ioKit: IOKitInterface
    
    /// Synchronization queue for IOKit operations
    private let ioQueue: DispatchQueue
    
    // MARK: - Initialization
    
    public init(device: USBDevice, interfaceNumber: UInt8, ioKit: IOKitInterface = RealIOKitInterface()) throws {
        self.device = device
        self.interfaceNumber = interfaceNumber
        self.ioKit = ioKit
        self.logger = Logger(subsystem: "com.usbipd.core", category: "IOKitUSBInterface")
        self.ioQueue = DispatchQueue(label: "com.usbipd.iokit-interface", qos: .userInitiated)
        
        try initializeIOKitReferences()
    }
    
    deinit {
        do {
            try close()
        } catch {
            logger.error("Failed to close USB interface during deinitialization: \(error)")
        }
        
        // Release IOKit references - placeholder implementation
        // In a real implementation, we would properly release IOKit interfaces
        deviceInterface = nil
        interfaceRefs.removeAll()
        
        if deviceRef != 0 {
            IOObjectRelease(deviceRef)
        }
    }
    
    // MARK: - Interface Lifecycle
    
    /// Open the USB interface for communication
    public func open() throws {
        guard !isOpen else {
            logger.debug("USB interface \(interfaceNumber) already open")
            return
        }
        
        return try executeIOKitOperation(operation: "open interface") {
            // Open the device interface
            guard let deviceInterface = self.deviceInterface else {
                throw USBRequestError.deviceNotAvailable
            }
            
            // Open the USB device
            let openResult = deviceInterface.pointee.USBDeviceOpen(deviceInterface)
            guard openResult == kIOReturnSuccess else {
                self.logger.error("Failed to open USB device: \(openResult)")
                throw IOKitError.operationFailed("USBDeviceOpen", openResult)
            }
            
            // Find and open the specific USB interface
            try self.findAndOpenUSBInterface()
            
            self.isOpen = true
            self.logger.info("Successfully opened USB interface \(self.interfaceNumber)")
        }
    }
    
    /// Close the USB interface
    public func close() throws {
        guard isOpen else {
            logger.debug("USB interface \(interfaceNumber) already closed")
            return
        }
        
        return try executeIOKitOperation(operation: "close interface") {
            // Close all interface references
            for (endpoint, interface) in self.interfaceRefs {
                let result = interface.pointee.USBInterfaceClose(interface)
                if result != kIOReturnSuccess {
                    self.logger.warning("Failed to close interface endpoint \(endpoint): \(result)")
                }
                // Release the interface
                _ = interface.pointee.Release(interface)
            }
            self.interfaceRefs.removeAll()
            
            // Close device interface
            if let deviceInterface = self.deviceInterface {
                let result = deviceInterface.pointee.USBDeviceClose(deviceInterface)
                if result != kIOReturnSuccess {
                    self.logger.warning("Failed to close device interface: \(result)")
                }
                // Release the device interface
                _ = deviceInterface.pointee.Release(deviceInterface)
                self.deviceInterface = nil
            }
            
            self.isOpen = false
            self.logger.info("Successfully closed USB interface \(self.interfaceNumber)")
        }
    }
    
    // MARK: - Transfer Methods
    
    /// Execute a control transfer
    public func executeControlTransfer(
        endpoint: UInt8,
        setupPacket: Data,
        transferBuffer: Data?,
        timeout: UInt32
    ) async throws -> USBTransferResult {
        guard isOpen else {
            throw USBRequestError.deviceNotAvailable
        }
        
        guard setupPacket.count == 8 else {
            throw USBRequestError.setupPacketInvalid
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    let result = try self.performControlTransfer(
                        endpoint: endpoint,
                        setupPacket: setupPacket,
                        transferBuffer: transferBuffer,
                        timeout: timeout
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Execute a bulk transfer
    public func executeBulkTransfer(
        endpoint: UInt8,
        data: Data?,
        bufferLength: UInt32,
        timeout: UInt32
    ) async throws -> USBTransferResult {
        guard isOpen else {
            throw USBRequestError.deviceNotAvailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    let result = try self.performBulkTransfer(
                        endpoint: endpoint,
                        data: data,
                        bufferLength: bufferLength,
                        timeout: timeout
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Execute an interrupt transfer
    public func executeInterruptTransfer(
        endpoint: UInt8,
        data: Data?,
        bufferLength: UInt32,
        timeout: UInt32
    ) async throws -> USBTransferResult {
        guard isOpen else {
            throw USBRequestError.deviceNotAvailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    let result = try self.performInterruptTransfer(
                        endpoint: endpoint,
                        data: data,
                        bufferLength: bufferLength,
                        timeout: timeout
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Execute an isochronous transfer
    public func executeIsochronousTransfer(
        endpoint: UInt8,
        data: Data?,
        bufferLength: UInt32,
        startFrame: UInt32,
        numberOfPackets: UInt32
    ) async throws -> USBTransferResult {
        guard isOpen else {
            throw USBRequestError.deviceNotAvailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    let result = try self.performIsochronousTransfer(
                        endpoint: endpoint,
                        data: data,
                        bufferLength: bufferLength,
                        startFrame: startFrame,
                        numberOfPackets: numberOfPackets
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Private Implementation Methods
    
    private func initializeIOKitReferences() throws {
        // Find the IOKit service for this USB device
        deviceRef = try findIOKitServiceForDevice()
        
        // Create device plugin interface
        deviceInterface = try createDevicePluginInterface()
        
        logger.info("Successfully initialized IOKit references for device \(device.busID)")
    }
    
    private func findIOKitServiceForDevice() throws -> io_service_t {
        // Create matching dictionary for USB devices
        guard let matchingDict = ioKit.serviceMatching(kIOUSBDeviceClassName) else {
            logger.error("Failed to create USB device matching dictionary")
            throw IOKitError.serviceNotFound("Failed to create matching dictionary")
        }
        
        // Add vendor and product ID constraints
        let vendorIDNumber = NSNumber(value: device.vendorID)
        let productIDNumber = NSNumber(value: device.productID)
        
        CFDictionarySetValue(matchingDict, Unmanaged.passUnretained(kUSBVendorID as CFString).toOpaque(), Unmanaged.passUnretained(vendorIDNumber).toOpaque())
        CFDictionarySetValue(matchingDict, Unmanaged.passUnretained(kUSBProductID as CFString).toOpaque(), Unmanaged.passUnretained(productIDNumber).toOpaque())
        
        // Get matching services
        var iterator: io_iterator_t = 0
        let result = ioKit.serviceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iterator)
        
        guard result == KERN_SUCCESS else {
            logger.error("Failed to get matching USB services: \(result)")
            throw IOKitError.serviceNotFound("IOServiceGetMatchingServices failed with result: \(result)")
        }
        
        defer {
            _ = ioKit.objectRelease(iterator)
        }
        
        // Find the specific device by bus ID if multiple matches
        let serviceRef = ioKit.iteratorNext(iterator)
        guard serviceRef != 0 else {
            logger.error("No USB device found matching vendor ID \(device.vendorID), product ID \(device.productID)")
            throw IOKitError.serviceNotFound("No matching USB device found")
        }
        
        logger.debug("Found IOKit service for USB device: \(device.busID)")
        return serviceRef
    }
    
    private func createDevicePluginInterface() throws -> UnsafeMutablePointer<IOUSBDeviceInterface300>? {
        guard deviceRef != 0 else {
            throw IOKitError.invalidReference("Invalid device reference")
        }
        
        // Create plugin interface
        var pluginInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        
        let result = IOCreatePlugInInterfaceForService(
            deviceRef,
            kIOUSBDeviceUserClientTypeID,
            kIOCFPlugInInterfaceID,
            &pluginInterface,
            &score
        )
        
        guard result == kIOReturnSuccess, let plugin = pluginInterface else {
            logger.error("Failed to create plugin interface: \(result)")
            throw IOKitError.pluginCreationFailed("IOCreatePlugInInterfaceForService", result)
        }
        
        defer {
            // Release the plugin interface after we're done with it
            _ = plugin.pointee?.pointee.Release(plugin)
        }
        
        // Query for the device interface
        var deviceInterface: UnsafeMutableRawPointer?
        let queryResult = plugin.pointee?.pointee.QueryInterface(
            plugin,
            CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID300),
            &deviceInterface
        )
        
        guard queryResult == S_OK, let deviceInterfacePtr = deviceInterface else {
            logger.error("Failed to query device interface: \(String(describing: queryResult))")
            throw IOKitError.interfaceCreationFailed("QueryInterface for device", IOReturn(queryResult ?? -2147483640))
        }
        
        let usbDeviceInterface = deviceInterfacePtr.assumingMemoryBound(to: IOUSBDeviceInterface300.self)
        logger.debug("Successfully created device plugin interface")
        
        return usbDeviceInterface
    }
    
    private func findAndOpenUSBInterface() throws {
        guard self.deviceInterface != nil else {
            throw USBRequestError.deviceNotAvailable
        }
        
        // For now, create a simplified interface setup
        // In a full implementation, we would iterate through actual USB interfaces
        // This is a placeholder that establishes the interface tracking structure
        
        logger.debug("Setting up interface tracking for interface \(interfaceNumber)")
        // Note: Full interface discovery will be implemented when we add endpoint discovery
    }
    
    // Note: openSpecificInterface method removed - will be implemented in task 4 when we add transfer execution
    
    private func performControlTransfer(
        endpoint: UInt8,
        setupPacket: Data,
        transferBuffer: Data?,
        timeout: UInt32
    ) throws -> USBTransferResult {
        
        guard self.deviceInterface != nil else {
            throw USBRequestError.deviceNotAvailable
        }
        
        // Extract setup packet components
        let setupBytes = setupPacket.withUnsafeBytes { bytes in
            bytes.bindMemory(to: UInt8.self)
        }
        
        let bmRequestType = setupBytes[0]
        let bRequest = setupBytes[1]
        let wValue = UInt16(setupBytes[2]) | (UInt16(setupBytes[3]) << 8)
        let wIndex = UInt16(setupBytes[4]) | (UInt16(setupBytes[5]) << 8)
        let wLength = UInt16(setupBytes[6]) | (UInt16(setupBytes[7]) << 8)
        
        // Prepare data buffer
        var dataBuffer: UnsafeMutablePointer<UInt8>? = nil
        var actualLength: UInt32 = 0
        
        if let transferBuffer = transferBuffer, !transferBuffer.isEmpty {
            dataBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: transferBuffer.count)
            _ = transferBuffer.copyBytes(to: UnsafeMutableBufferPointer(start: dataBuffer!, count: transferBuffer.count))
        } else if wLength > 0 {
            dataBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(wLength))
        }
        
        defer {
            dataBuffer?.deallocate()
        }
        
        // Create IOKit request structure
        var request = IOUSBDevRequest()
        request.bmRequestType = bmRequestType
        request.bRequest = bRequest
        request.wValue = wValue
        request.wIndex = wIndex
        request.wLength = wLength
        request.pData = UnsafeMutableRawPointer(dataBuffer)
        request.wLenDone = 0
        
        // Execute the control transfer
        let _ = Date().timeIntervalSince1970  // startTime for potential timing measurements
        // This is a placeholder implementation since IOKit interfaces are complex
        // In a real implementation, we would need to properly initialize IOKit interfaces
        let result = kIOReturnUnsupported
        let completionTime = Date().timeIntervalSince1970
        
        // Process result
        let status = USBErrorMapping.mapIOKitError(result)
        actualLength = UInt32(request.wLenDone)
        
        // Copy received data for IN transfers
        var receivedData: Data? = nil
        if result == kIOReturnSuccess && actualLength > 0 && (bmRequestType & 0x80) != 0 {
            receivedData = Data(bytes: dataBuffer!, count: Int(actualLength))
        }
        
        return USBTransferResult(
            status: USBStatus(rawValue: status) ?? .requestFailed,
            actualLength: actualLength,
            data: receivedData,
            completionTime: completionTime
        )
    }
    
    private func performBulkTransfer(
        endpoint: UInt8,
        data: Data?,
        bufferLength: UInt32,
        timeout: UInt32
    ) throws -> USBTransferResult {
        
        // Bulk transfers require interface reference for specific endpoint
        // This is a placeholder implementation
        
        _ = Date().timeIntervalSince1970
        let completionTime = Date().timeIntervalSince1970
        
        // For now, return a placeholder result
        // Real implementation would use interface.WritePipe or ReadPipe
        
        return USBTransferResult(
            status: USBStatus.requestFailed,
            actualLength: 0,
            completionTime: completionTime
        )
    }
    
    private func performInterruptTransfer(
        endpoint: UInt8,
        data: Data?,
        bufferLength: UInt32,
        timeout: UInt32
    ) throws -> USBTransferResult {
        
        // Interrupt transfers are similar to bulk but with different timing
        // This is a placeholder implementation
        
        _ = Date().timeIntervalSince1970
        let completionTime = Date().timeIntervalSince1970
        
        // For now, return a placeholder result
        // Real implementation would use interface methods with interrupt-specific handling
        
        return USBTransferResult(
            status: USBStatus.requestFailed,
            actualLength: 0,
            completionTime: completionTime
        )
    }
    
    private func performIsochronousTransfer(
        endpoint: UInt8,
        data: Data?,
        bufferLength: UInt32,
        startFrame: UInt32,
        numberOfPackets: UInt32
    ) throws -> USBTransferResult {
        
        // Isochronous transfers are the most complex, requiring frame scheduling
        // This is a placeholder implementation
        
        let completionTime = Date().timeIntervalSince1970
        
        // For now, return a placeholder result
        // Real implementation would use interface methods with frame management
        
        return USBTransferResult(
            status: USBStatus.requestFailed,
            actualLength: 0,
            errorCount: 0,
            completionTime: completionTime,
            startFrame: startFrame
        )
    }
    
    // MARK: - Helper Methods
    
    private func executeIOKitOperation<T>(operation: String, block: () throws -> T) throws -> T {
        do {
            logger.debug("Executing IOKit operation: \(operation)")
            return try block()
        } catch let error as IOKitError {
            logger.error("IOKit operation '\(operation)' failed: \(error)")
            throw error
        } catch {
            logger.error("IOKit operation '\(operation)' failed with unexpected error: \(error)")
            throw USBRequestError.requestFailed
        }
    }
}

// MARK: - IOKit Error Handling

/// IOKit-specific errors for USB interface operations
public enum IOKitError: Error {
    case serviceNotFound(String)
    case pluginCreationFailed(String, IOReturn)
    case interfaceCreationFailed(String, IOReturn)
    case operationFailed(String, IOReturn)
    case invalidReference(String)
}

extension IOKitError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .serviceNotFound(let device):
            return "IOKit service not found for device: \(device)"
        case .pluginCreationFailed(let operation, let result):
            return "IOKit plugin creation failed for \(operation): \(result)"
        case .interfaceCreationFailed(let interface, let result):
            return "IOKit interface creation failed for \(interface): \(result)"
        case .operationFailed(let operation, let result):
            return "IOKit operation failed: \(operation) (result: \(result))"
        case .invalidReference(let reference):
            return "Invalid IOKit reference: \(reference)"
        }
    }
}