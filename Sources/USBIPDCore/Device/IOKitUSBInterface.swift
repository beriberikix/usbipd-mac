// IOKitUSBInterface.swift
// IOKit USB interface wrapper with all transfer types

import Foundation
import IOKit
import IOKit.usb
import Common

// IOKit constants manually defined since macros are unavailable
private let kIOUSBDeviceUserClientTypeID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x9d, 0xc7, 0xb7, 0x80, 0x9e, 0xc0, 0x11, 0xd4,
    0xa5, 0x4f, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

private let kIOCFPlugInInterfaceID = CFUUIDGetConstantUUIDWithBytes(nil,
    0xc2, 0x44, 0xe8, 0x58, 0x10, 0x9c, 0x11, 0xd4,
    0x91, 0xd4, 0x00, 0x50, 0xe4, 0xc6, 0x42, 0x6f)

private let kIOUSBDeviceInterfaceID300 = CFUUIDGetConstantUUIDWithBytes(nil,
    0x39, 0x61, 0x04, 0xf7, 0x94, 0x3d, 0x48, 0x93,
    0x90, 0xf1, 0x69, 0xbd, 0x6c, 0xf5, 0xc2, 0xeb)

private let kIOUSBInterfaceUserClientTypeID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x2d, 0x97, 0x86, 0xc6, 0x9e, 0xf3, 0x11, 0xd4,
    0xad, 0x51, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

private let kIOUSBInterfaceInterfaceID300 = CFUUIDGetConstantUUIDWithBytes(nil,
    0xbc, 0xea, 0xad, 0xdc, 0x88, 0x4d, 0x4f, 0x27,
    0x83, 0x40, 0x36, 0xd6, 0x9f, 0xab, 0x90, 0xf6)

/// IOKit wrapper for USB interface communication
public final class IOKitUSBInterface: @unchecked Sendable {
    
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
        guard let deviceInterface = self.deviceInterface else {
            throw USBRequestError.deviceNotAvailable
        }
        
        // Create interface iterator with interface request
        var interfaceRequest = IOUSBFindInterfaceRequest()
        interfaceRequest.bInterfaceClass = UInt16(kIOUSBFindInterfaceDontCare)
        interfaceRequest.bInterfaceSubClass = UInt16(kIOUSBFindInterfaceDontCare)
        interfaceRequest.bInterfaceProtocol = UInt16(kIOUSBFindInterfaceDontCare)
        interfaceRequest.bAlternateSetting = UInt16(kIOUSBFindInterfaceDontCare)
        
        var interfaceIterator: io_iterator_t = 0
        let iteratorResult = deviceInterface.pointee.CreateInterfaceIterator(deviceInterface, &interfaceRequest, &interfaceIterator)
        
        guard iteratorResult == kIOReturnSuccess else {
            logger.error("Failed to create interface iterator: \(iteratorResult)")
            throw IOKitError.operationFailed("CreateInterfaceIterator", iteratorResult)
        }
        
        defer {
            _ = ioKit.objectRelease(interfaceIterator)
        }
        
        // Find and open the specific interface we need
        var currentInterfaceNum: UInt8 = 0
        var interfaceService = ioKit.iteratorNext(interfaceIterator)
        
        while interfaceService != 0 {
            defer {
                _ = ioKit.objectRelease(interfaceService)
                interfaceService = ioKit.iteratorNext(interfaceIterator)
            }
            
            // Check if this is the interface we want
            if currentInterfaceNum == interfaceNumber {
                try openSpecificInterface(interfaceService)
                return
            }
            
            currentInterfaceNum += 1
        }
        
        throw IOKitError.interfaceCreationFailed("Interface \(interfaceNumber) not found", kIOReturnNotFound)
    }
    
    private func openSpecificInterface(_ interfaceService: io_service_t) throws {
        // Create plugin interface for this specific interface
        var pluginInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        
        let pluginResult = IOCreatePlugInInterfaceForService(
            interfaceService,
            kIOUSBInterfaceUserClientTypeID,
            kIOCFPlugInInterfaceID,
            &pluginInterface,
            &score
        )
        
        guard pluginResult == kIOReturnSuccess, let plugin = pluginInterface else {
            logger.error("Failed to create interface plugin: \(pluginResult)")
            throw IOKitError.pluginCreationFailed("Interface plugin creation", pluginResult)
        }
        
        defer {
            _ = plugin.pointee?.pointee.Release(plugin)
        }
        
        // Query for the interface
        var usbInterface: UnsafeMutableRawPointer?
        let queryResult = plugin.pointee?.pointee.QueryInterface(
            plugin,
            CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300),
            &usbInterface
        )
        
        guard queryResult == S_OK, let interfacePtr = usbInterface else {
            logger.error("Failed to query interface: \(String(describing: queryResult))")
            throw IOKitError.interfaceCreationFailed("QueryInterface for interface", IOReturn(queryResult ?? -2147483640))
        }
        
        let interface = interfacePtr.assumingMemoryBound(to: IOUSBInterfaceInterface300.self)
        
        // Open the interface
        let openResult = interface.pointee.USBInterfaceOpen(interface)
        guard openResult == kIOReturnSuccess else {
            logger.error("Failed to open USB interface: \(openResult)")
            _ = interface.pointee.Release(interface)
            throw IOKitError.operationFailed("USBInterfaceOpen", openResult)
        }
        
        // Store the interface reference for endpoint 0 (will be enhanced with endpoint discovery)
        interfaceRefs[0] = interface
        logger.debug("Successfully opened USB interface \(interfaceNumber)")
        
        // TODO: Add endpoint discovery to populate interfaceRefs with proper pipe references
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
        
        // Validate transfer parameters
        guard timeout > 0 && timeout <= 60000 else {
            throw USBRequestError.timeoutInvalid(timeout)
        }
        
        guard setupPacket.count == 8 else {
            throw USBRequestError.setupPacketInvalid
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
        
        // Validate buffer size for OUT transfers (host to device)
        if (bmRequestType & 0x80) == 0 {  // OUT transfer
            if let transferBuffer = transferBuffer {
                guard transferBuffer.count == Int(wLength) else {
                    throw USBRequestError.bufferSizeMismatch(expected: UInt32(wLength), actual: UInt32(transferBuffer.count))
                }
            } else if wLength > 0 {
                throw USBRequestError.setupPacketInvalid
            }
        }
        
        logger.debug("Control transfer: bmRequestType=0x\(String(bmRequestType, radix: 16)), bRequest=0x\(String(bRequest, radix: 16)), wValue=0x\(String(wValue, radix: 16)), wIndex=0x\(String(wIndex, radix: 16)), wLength=\(wLength)")
        
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
        let startTime = Date().timeIntervalSince1970
        let result: IOReturn
        
        if let deviceInterface = self.deviceInterface {
            // Perform the actual IOKit device request
            result = deviceInterface.pointee.DeviceRequest(deviceInterface, &request)
            
            if result == kIOReturnSuccess {
                logger.debug("Control transfer completed successfully: \(request.wLenDone) bytes transferred")
            } else {
                logger.warning("Control transfer failed with IOKit result: \(result)")
            }
        } else {
            logger.error("Device interface not available for control transfer")
            result = kIOReturnNoDevice
        }
        
        let completionTime = Date().timeIntervalSince1970
        logger.debug("Control transfer took \((completionTime - startTime) * 1000)ms")
        
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
        
        // Validate parameters
        guard timeout > 0 && timeout <= 60000 else {
            throw USBRequestError.timeoutInvalid(timeout)
        }
        
        guard bufferLength > 0 else {
            throw USBRequestError.invalidParameters
        }
        
        // Check if this is an IN or OUT transfer based on endpoint direction
        let isInTransfer = (endpoint & 0x80) != 0
        let pipeRef = endpoint & 0x7F  // Remove direction bit to get pipe reference
        
        logger.debug("Bulk transfer: endpoint=0x\(String(endpoint, radix: 16)), direction=\(isInTransfer ? "IN" : "OUT"), bufferLength=\(bufferLength)")
        
        // Get interface reference (using endpoint 0 for now, will be enhanced with proper endpoint discovery)
        guard let interface = interfaceRefs[0] else {
            logger.error("No interface reference available for bulk transfer")
            throw USBRequestError.deviceNotAvailable
        }
        
        let startTime = Date().timeIntervalSince1970
        var actualLength: UInt32 = 0
        var transferData: Data?
        let result: IOReturn
        
        if isInTransfer {
            // IN transfer (device to host) - ReadPipe
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(bufferLength))
            defer { buffer.deallocate() }
            
            result = interface.pointee.ReadPipe(interface, pipeRef, buffer, &actualLength)
            
            if result == kIOReturnSuccess && actualLength > 0 {
                transferData = Data(bytes: buffer, count: Int(actualLength))
                logger.debug("Bulk IN transfer completed: \(actualLength) bytes read")
            } else {
                logger.warning("Bulk IN transfer failed with result: \(result)")
            }
        } else {
            // OUT transfer (host to device) - WritePipe
            if let data = data {
                guard data.count <= Int(bufferLength) else {
                    throw USBRequestError.bufferSizeMismatch(expected: bufferLength, actual: UInt32(data.count))
                }
                
                actualLength = UInt32(data.count)
                result = data.withUnsafeBytes { bytes in
                    let buffer = UnsafeMutableRawPointer(mutating: bytes.baseAddress!)
                    return interface.pointee.WritePipe(interface, pipeRef, buffer, actualLength)
                }
                
                if result == kIOReturnSuccess {
                    logger.debug("Bulk OUT transfer completed: \(actualLength) bytes written")
                } else {
                    logger.warning("Bulk OUT transfer failed with result: \(result)")
                }
            } else {
                logger.error("No data provided for bulk OUT transfer")
                result = kIOReturnBadArgument
            }
        }
        
        let completionTime = Date().timeIntervalSince1970
        logger.debug("Bulk transfer took \((completionTime - startTime) * 1000)ms")
        
        // Map result and return
        let status = USBErrorMapping.mapIOKitError(result)
        
        return USBTransferResult(
            status: USBStatus(rawValue: status) ?? .requestFailed,
            actualLength: actualLength,
            data: transferData,
            completionTime: completionTime
        )
    }
    
    private func performInterruptTransfer(
        endpoint: UInt8,
        data: Data?,
        bufferLength: UInt32,
        timeout: UInt32
    ) throws -> USBTransferResult {
        
        // Validate parameters
        guard timeout > 0 && timeout <= 60000 else {
            throw USBRequestError.timeoutInvalid(timeout)
        }
        
        guard bufferLength > 0 && bufferLength <= 8192 else {  // Interrupt transfers typically have smaller payloads
            throw USBRequestError.invalidParameters
        }
        
        // Check if this is an IN or OUT transfer based on endpoint direction
        let isInTransfer = (endpoint & 0x80) != 0
        let pipeRef = endpoint & 0x7F  // Remove direction bit to get pipe reference
        
        logger.debug("Interrupt transfer: endpoint=0x\(String(endpoint, radix: 16)), direction=\(isInTransfer ? "IN" : "OUT"), bufferLength=\(bufferLength)")
        
        // Get interface reference (using endpoint 0 for now, will be enhanced with proper endpoint discovery)
        guard let interface = interfaceRefs[0] else {
            logger.error("No interface reference available for interrupt transfer")
            throw USBRequestError.deviceNotAvailable
        }
        
        let startTime = Date().timeIntervalSince1970
        var actualLength: UInt32 = 0
        var transferData: Data?
        let result: IOReturn
        
        if isInTransfer {
            // IN transfer (device to host) - ReadPipeTO with timeout for interrupt handling
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(bufferLength))
            defer { buffer.deallocate() }
            
            // Use timeout-based read for interrupt transfers to handle periodic polling
            result = interface.pointee.ReadPipeTO(interface, pipeRef, buffer, &actualLength, timeout, timeout)
            
            if result == kIOReturnSuccess && actualLength > 0 {
                transferData = Data(bytes: buffer, count: Int(actualLength))
                logger.debug("Interrupt IN transfer completed: \(actualLength) bytes read")
            } else if result == kIOReturnTimeout {
                logger.debug("Interrupt IN transfer timed out (normal for polling)")
            } else {
                logger.warning("Interrupt IN transfer failed with result: \(result)")
            }
        } else {
            // OUT transfer (host to device) - WritePipeTO with timeout
            if let data = data {
                guard data.count <= Int(bufferLength) else {
                    throw USBRequestError.bufferSizeMismatch(expected: bufferLength, actual: UInt32(data.count))
                }
                
                actualLength = UInt32(data.count)
                result = data.withUnsafeBytes { bytes in
                    let buffer = UnsafeMutableRawPointer(mutating: bytes.baseAddress!)
                    return interface.pointee.WritePipeTO(interface, pipeRef, buffer, actualLength, timeout, timeout)
                }
                
                if result == kIOReturnSuccess {
                    logger.debug("Interrupt OUT transfer completed: \(actualLength) bytes written")
                } else {
                    logger.warning("Interrupt OUT transfer failed with result: \(result)")
                }
            } else {
                logger.error("No data provided for interrupt OUT transfer")
                result = kIOReturnBadArgument
            }
        }
        
        let completionTime = Date().timeIntervalSince1970
        logger.debug("Interrupt transfer took \((completionTime - startTime) * 1000)ms")
        
        // Map result and return
        let status = USBErrorMapping.mapIOKitError(result)
        
        return USBTransferResult(
            status: USBStatus(rawValue: status) ?? .requestFailed,
            actualLength: actualLength,
            data: transferData,
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
        
        // Validate parameters for isochronous transfers
        guard numberOfPackets > 0 && numberOfPackets <= 1024 else {  // Reasonable limit for frame packets
            throw USBRequestError.invalidParameters
        }
        
        guard bufferLength > 0 else {
            throw USBRequestError.invalidParameters
        }
        
        // Check if this is an IN or OUT transfer based on endpoint direction
        let isInTransfer = (endpoint & 0x80) != 0
        let pipeRef = endpoint & 0x7F  // Remove direction bit to get pipe reference
        
        logger.debug("Isochronous transfer: endpoint=0x\(String(endpoint, radix: 16)), direction=\(isInTransfer ? "IN" : "OUT"), bufferLength=\(bufferLength), startFrame=\(startFrame), packets=\(numberOfPackets)")
        
        // Get interface reference (using endpoint 0 for now, will be enhanced with proper endpoint discovery)
        guard let interface = interfaceRefs[0] else {
            logger.error("No interface reference available for isochronous transfer")
            throw USBRequestError.deviceNotAvailable
        }
        
        let startTime = Date().timeIntervalSince1970
        var actualLength: UInt32 = 0
        var transferData: Data?
        var errorCount: UInt32 = 0
        let result: IOReturn
        var actualStartFrame = UInt64(startFrame)
        
        // Calculate packet size - distribute buffer evenly across packets
        let packetSize = bufferLength / numberOfPackets
        guard packetSize > 0 else {
            throw USBRequestError.invalidParameters
        }
        
        if isInTransfer {
            // IN transfer (device to host) - ReadIsochPipeAsync for frame-based reading
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(bufferLength))
            defer { buffer.deallocate() }
            
            // Allocate frame list for isochronous transfer tracking
            let frameList = UnsafeMutablePointer<IOUSBIsocFrame>.allocate(capacity: Int(numberOfPackets))
            defer { frameList.deallocate() }
            
            // Initialize frame list with packet sizes
            for i in 0..<Int(numberOfPackets) {
                frameList[i].frStatus = kIOReturnInvalid  // Initialize status
                frameList[i].frReqCount = UInt16(packetSize)
                frameList[i].frActCount = 0
            }
            
            // If startFrame is 0, get current frame and schedule for near future
            if actualStartFrame == 0 {
                var currentFrame: UInt64 = 0
                let frameResult = interface.pointee.GetBusFrameNumber(interface, &currentFrame, nil)
                if frameResult == kIOReturnSuccess {
                    actualStartFrame = currentFrame + 10  // Schedule 10 frames in future
                } else {
                    actualStartFrame = 100  // Fallback value
                }
            }
            
            // Perform isochronous read
            result = interface.pointee.ReadIsochPipeAsync(
                interface,
                pipeRef,
                buffer,
                actualStartFrame,
                numberOfPackets,
                frameList,
                nil,  // No async callback for synchronous operation
                nil   // No refCon
            )
            
            if result == kIOReturnSuccess {
                // Calculate total transferred data and error count
                actualLength = 0
                errorCount = 0
                for i in 0..<Int(numberOfPackets) {
                    actualLength += UInt32(frameList[i].frActCount)
                    if frameList[i].frStatus != kIOReturnSuccess {
                        errorCount += 1
                    }
                }
                
                if actualLength > 0 {
                    transferData = Data(bytes: buffer, count: Int(actualLength))
                }
                
                logger.debug("Isochronous IN transfer completed: \(actualLength) bytes read, \(errorCount) packet errors")
            } else {
                logger.warning("Isochronous IN transfer failed with result: \(result)")
            }
        } else {
            // OUT transfer (host to device) - WriteIsochPipeAsync for frame-based writing
            if let data = data {
                guard data.count <= Int(bufferLength) else {
                    throw USBRequestError.bufferSizeMismatch(expected: bufferLength, actual: UInt32(data.count))
                }
                
                // Allocate frame list for isochronous transfer tracking
                let frameList = UnsafeMutablePointer<IOUSBIsocFrame>.allocate(capacity: Int(numberOfPackets))
                defer { frameList.deallocate() }
                
                // Initialize frame list with packet sizes
                var remainingData = data.count
                for i in 0..<Int(numberOfPackets) {
                    let currentPacketSize = min(remainingData, Int(packetSize))
                    frameList[i].frStatus = kIOReturnInvalid
                    frameList[i].frReqCount = UInt16(currentPacketSize)
                    frameList[i].frActCount = 0
                    remainingData -= currentPacketSize
                }
                
                // If startFrame is 0, get current frame and schedule for near future
                if actualStartFrame == 0 {
                    var currentFrame: UInt64 = 0
                    let frameResult = interface.pointee.GetBusFrameNumber(interface, &currentFrame, nil)
                    if frameResult == kIOReturnSuccess {
                        actualStartFrame = currentFrame + 10  // Schedule 10 frames in future
                    } else {
                        actualStartFrame = 100  // Fallback value
                    }
                }
                
                actualLength = UInt32(data.count)
                result = data.withUnsafeBytes { bytes in
                    let buffer = UnsafeMutableRawPointer(mutating: bytes.baseAddress!)
                    return interface.pointee.WriteIsochPipeAsync(
                        interface,
                        pipeRef,
                        buffer,
                        actualStartFrame,
                        numberOfPackets,
                        frameList,
                        nil,  // No async callback for synchronous operation
                        nil   // No refCon
                    )
                }
                
                if result == kIOReturnSuccess {
                    // Calculate error count from frame results
                    errorCount = 0
                    for i in 0..<Int(numberOfPackets) where frameList[i].frStatus != kIOReturnSuccess {
                        errorCount += 1
                    }
                    logger.debug("Isochronous OUT transfer completed: \(actualLength) bytes written, \(errorCount) packet errors")
                } else {
                    logger.warning("Isochronous OUT transfer failed with result: \(result)")
                }
            } else {
                logger.error("No data provided for isochronous OUT transfer")
                result = kIOReturnBadArgument
            }
        }
        
        let completionTime = Date().timeIntervalSince1970
        logger.debug("Isochronous transfer took \((completionTime - startTime) * 1000)ms")
        
        // Map result and return
        let status = USBErrorMapping.mapIOKitError(result)
        
        return USBTransferResult(
            status: USBStatus(rawValue: status) ?? .requestFailed,
            actualLength: actualLength,
            errorCount: errorCount,
            data: transferData,
            completionTime: completionTime,
            startFrame: UInt32(actualStartFrame)
        )
    }
    
    // MARK: - Transfer Cancellation
    
    /// Cancel all pending transfers on all pipes
    /// This attempts to abort any ongoing USB transfers on the interface
    public func cancelAllTransfers() throws {
        logger.debug("Cancelling all pending transfers on interface \(interfaceNumber)")
        
        guard isOpen else {
            logger.warning("Cannot cancel transfers - interface not open")
            return
        }
        
        // Cancel transfers on all active interface references
        for (endpoint, interface) in interfaceRefs {
            do {
                try cancelTransfersOnInterface(interface, endpoint: endpoint)
            } catch {
                logger.warning("Failed to cancel transfers on endpoint \(endpoint): \(error)")
                // Continue attempting to cancel other endpoints
            }
        }
        
        logger.info("Transfer cancellation completed for interface \(interfaceNumber)")
    }
    
    /// Cancel transfers on a specific endpoint
    /// - Parameter endpoint: The endpoint address to cancel transfers on
    public func cancelTransfers(endpoint: UInt8) throws {
        logger.debug("Cancelling transfers on endpoint 0x\(String(endpoint, radix: 16))")
        
        guard isOpen else {
            logger.warning("Cannot cancel transfers - interface not open")
            return
        }
        
        // Find the interface reference for this endpoint
        // For now, use endpoint 0 as the default interface reference
        // In production, this would map to proper interface/endpoint relationships
        let interfaceKey: UInt8 = 0
        
        guard let interface = interfaceRefs[interfaceKey] else {
            logger.warning("No interface reference available for endpoint 0x\(String(endpoint, radix: 16))")
            return
        }
        
        try cancelTransfersOnInterface(interface, endpoint: endpoint)
        logger.info("Transfer cancellation completed for endpoint 0x\(String(endpoint, radix: 16))")
    }
    
    /// Internal method to cancel transfers on a specific interface reference
    private func cancelTransfersOnInterface(_ interface: UnsafeMutablePointer<IOUSBInterfaceInterface300>, endpoint: UInt8) throws {
        let pipeRef = endpoint & 0x7F  // Remove direction bit
        
        // Abort transfers on the specific pipe
        let result = interface.pointee.AbortPipe(interface, pipeRef)
        
        if result != kIOReturnSuccess {
            logger.warning("AbortPipe failed for endpoint 0x\(String(endpoint, radix: 16)): \(result)")
            // Don't throw error as this might be expected if no transfers are pending
        } else {
            logger.debug("Successfully aborted transfers on pipe \(pipeRef)")
        }
        
        // Clear any stall condition that might have been caused by the abort
        let clearResult = interface.pointee.ClearPipeStall(interface, pipeRef)
        if clearResult != kIOReturnSuccess {
            logger.warning("ClearPipeStall failed for endpoint 0x\(String(endpoint, radix: 16)): \(clearResult)")
        }
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