// TestDeviceSimulator.swift
// USB device simulator for QEMU testing

import Foundation
import Common
import USBIPDCore

/// Test device simulator that provides mock USB devices for protocol testing
public class TestDeviceSimulator: DeviceDiscovery {
    private let logger: Logger
    private let devices: [USBDevice]
    private let deviceClaimManager: DeviceClaimManager
    private var isMonitoring = false
    
    /// Callback for device connection events
    public var onDeviceConnected: ((USBDevice) -> Void)?
    
    /// Callback for device disconnection events
    public var onDeviceDisconnected: ((USBDevice) -> Void)?
    
    /// Initialize with test devices and claim manager
    public init(logger: Logger) {
        self.logger = logger
        self.deviceClaimManager = MockDeviceClaimManager()
        
        // Create a comprehensive set of test devices for various scenarios
        self.devices = [
            // HID Mouse Device
            USBDevice(
                busID: "1-1",
                deviceID: "1.0",
                vendorID: 0x046D,  // Logitech
                productID: 0xC077,  // M105 Mouse
                deviceClass: 3,     // HID
                deviceSubClass: 1,  // Boot Interface
                deviceProtocol: 2,  // Mouse
                speed: .full,
                manufacturerString: "Logitech",
                productString: "USB Optical Mouse",
                serialNumberString: "TEST-MOUSE-001"
            ),
            
            // HID Keyboard Device  
            USBDevice(
                busID: "1-2",
                deviceID: "1.0", 
                vendorID: 0x413C,  // Dell
                productID: 0x2113,  // KB216
                deviceClass: 3,     // HID
                deviceSubClass: 1,  // Boot Interface
                deviceProtocol: 1,  // Keyboard
                speed: .full,
                manufacturerString: "Dell",
                productString: "Dell USB Keyboard",
                serialNumberString: "TEST-KEYBOARD-001"
            ),
            
            // USB Hub Device
            USBDevice(
                busID: "1-3",
                deviceID: "1.0",
                vendorID: 0x2109,  // VIA Labs
                productID: 0x3431,  // USB 3.0 Hub
                deviceClass: 9,     // Hub
                deviceSubClass: 0,
                deviceProtocol: 1,  // Single TT
                speed: .high,
                manufacturerString: "VIA Labs, Inc.",
                productString: "USB3.0 Hub",
                serialNumberString: "TEST-HUB-001"
            ),
            
            // Mass Storage Device (USB Drive)
            USBDevice(
                busID: "1-4",
                deviceID: "1.0",
                vendorID: 0x0781,  // SanDisk
                productID: 0x5567,  // Cruzer Blade
                deviceClass: 8,     // Mass Storage
                deviceSubClass: 6,  // SCSI Transparent Command Set
                deviceProtocol: 80, // Bulk-Only Transport
                speed: .high,
                manufacturerString: "SanDisk",
                productString: "Cruzer Blade",
                serialNumberString: "TEST-STORAGE-001"
            ),
            
            // CDC-ACM Serial Device
            USBDevice(
                busID: "1-5",
                deviceID: "1.0",
                vendorID: 0x2341,  // Arduino LLC
                productID: 0x0043,  // Arduino Uno Rev3
                deviceClass: 2,     // CDC-Communication
                deviceSubClass: 2,  // Abstract Control Model
                deviceProtocol: 1,  // AT Commands (v.25ter)
                speed: .full,
                manufacturerString: "Arduino LLC",
                productString: "Arduino Uno Rev3",
                serialNumberString: "TEST-SERIAL-001"
            ),
            
            // Audio Device
            USBDevice(
                busID: "1-6",
                deviceID: "1.0",
                vendorID: 0x0B05,  // ASUSTek Computer
                productID: 0x1234,  // USB Audio
                deviceClass: 1,     // Audio
                deviceSubClass: 1,  // Audio Control
                deviceProtocol: 0,
                speed: .full,
                manufacturerString: "ASUS",
                productString: "USB Audio Device",
                serialNumberString: "TEST-AUDIO-001"
            )
        ]
        
        logger.info("TestDeviceSimulator initialized", context: [
            "deviceCount": devices.count
        ])
        
        // Log each test device for debugging
        for (index, device) in devices.enumerated() {
            logger.debug("Test device initialized", context: [
                "index": index,
                "busID": device.busID,
                "deviceID": device.deviceID,
                "vendorID": String(format: "0x%04x", device.vendorID),
                "productID": String(format: "0x%04x", device.productID),
                "deviceClass": device.deviceClass,
                "product": device.productString ?? "Unknown"
            ])
        }
    }
    
    /// Get the device claim manager for this simulator
    public func getDeviceClaimManager() -> DeviceClaimManager {
        return deviceClaimManager
    }
    
    // MARK: - DeviceDiscovery Implementation
    
    /// Discover all simulated USB devices
    public func discoverDevices() throws -> [USBDevice] {
        logger.info("Discovering simulated devices", context: [
            "deviceCount": devices.count
        ])
        return devices
    }
    
    /// Get a specific device by bus ID and device ID
    public func getDevice(busID: String, deviceID: String) throws -> USBDevice? {
        logger.debug("Looking for device", context: [
            "busID": busID,
            "deviceID": deviceID
        ])
        
        let device = devices.first { 
            $0.busID == busID && $0.deviceID == deviceID 
        }
        
        if let device = device {
            logger.debug("Found device", context: [
                "busID": device.busID,
                "deviceID": device.deviceID,
                "product": device.productString ?? "Unknown"
            ])
        } else {
            logger.warning("Device not found", context: [
                "busID": busID,
                "deviceID": deviceID
            ])
        }
        
        return device
    }
    
    /// Start monitoring for device notifications (simulated)
    public func startNotifications() throws {
        guard !isMonitoring else {
            logger.warning("Notifications already started")
            return
        }
        
        isMonitoring = true
        logger.info("Started device notifications monitoring")
        
        // Simulate some device connection events after a delay
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
            self.simulateDeviceEvents()
        }
    }
    
    /// Stop monitoring for device notifications
    public func stopNotifications() {
        guard isMonitoring else {
            logger.warning("Notifications not started")
            return
        }
        
        isMonitoring = false
        logger.info("Stopped device notifications monitoring")
    }
    
    // MARK: - Device Event Simulation
    
    /// Simulate device connection and disconnection events
    private func simulateDeviceEvents() {
        guard isMonitoring else { return }
        
        // Simulate device connection event for first device
        if let firstDevice = devices.first {
            logger.debug("Simulating device connection", context: [
                "busID": firstDevice.busID,
                "product": firstDevice.productString ?? "Unknown"
            ])
            onDeviceConnected?(firstDevice)
        }
        
        // Schedule a disconnection event
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5.0) {
            guard self.isMonitoring else { return }
            
            if let firstDevice = self.devices.first {
                self.logger.debug("Simulating device disconnection", context: [
                    "busID": firstDevice.busID,
                    "product": firstDevice.productString ?? "Unknown"
                ])
                self.onDeviceDisconnected?(firstDevice)
            }
            
            // Schedule reconnection
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3.0) {
                self.simulateDeviceEvents()
            }
        }
    }
    
    // MARK: - Device Management Utilities
    
    /// Get device by USB/IP bus ID format (includes interface)
    public func getDeviceByUSBIPBusID(_ busID: String) throws -> USBDevice? {
        logger.debug("Looking for device by USB/IP busID", context: [
            "busID": busID
        ])
        
        // Parse USB/IP bus ID format (e.g., "1-1:1.0")
        let components = busID.split(separator: ":")
        guard components.count >= 1 else {
            logger.warning("Invalid USB/IP busID format", context: [
                "busID": busID
            ])
            throw DeviceError.deviceNotFound("Invalid busID format: \(busID)")
        }
        
        let deviceBusID = String(components[0])
        let deviceID = components.count > 1 ? String(components[1]) : "1.0"
        
        return try getDevice(busID: deviceBusID, deviceID: deviceID)
    }
    
    /// Get all devices of a specific class
    public func getDevicesByClass(_ deviceClass: UInt8) -> [USBDevice] {
        let classDevices = devices.filter { $0.deviceClass == deviceClass }
        
        logger.debug("Found devices by class", context: [
            "deviceClass": deviceClass,
            "count": classDevices.count
        ])
        
        return classDevices
    }
    
    /// Get device statistics for testing
    public func getDeviceStatistics() -> [String: Any] {
        let classCounts = Dictionary(grouping: devices, by: { $0.deviceClass })
            .mapValues { $0.count }
        
        let speedCounts = Dictionary(grouping: devices, by: { $0.speed })
            .mapValues { $0.count }
        
        return [
            "totalDevices": devices.count,
            "devicesByClass": classCounts,
            "devicesBySpeed": speedCounts,
            "isMonitoring": isMonitoring
        ]
    }
}

/// Extended test request processor that uses TestDeviceSimulator
public class SimulatedTestRequestProcessor {
    private let logger: Logger
    private let deviceSimulator: TestDeviceSimulator
    private let deviceClaimManager: DeviceClaimManager
    
    public init(logger: Logger) {
        self.logger = logger
        self.deviceSimulator = TestDeviceSimulator(logger: logger)
        self.deviceClaimManager = deviceSimulator.getDeviceClaimManager()
    }
    
    /// Process incoming USB/IP request using simulated devices
    public func processRequest(_ data: Data) throws -> Data {
        logger.debug("Processing USB/IP request with simulator", context: [
            "dataSize": data.count
        ])
        
        // Parse the header to determine request type
        guard data.count >= 8 else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        let header = try USBIPHeader.decode(from: data)
        logger.info("Processing simulated request", context: [
            "command": String(format: "0x%04x", header.command.rawValue),
            "status": header.status
        ])
        
        switch header.command {
        case .requestDeviceList:
            return try handleSimulatedDeviceListRequest(data)
            
        case .requestDeviceImport:
            return try handleSimulatedDeviceImportRequest(data)
            
        case .submitRequest:
            logger.warning("USB SUBMIT request simulation not implemented")
            throw USBIPProtocolError.unsupportedCommand(header.command.rawValue)
            
        case .unlinkRequest:
            logger.warning("USB UNLINK request simulation not implemented")
            throw USBIPProtocolError.unsupportedCommand(header.command.rawValue)
            
        default:
            logger.error("Unsupported command in simulator", context: [
                "command": String(format: "0x%04x", header.command.rawValue)
            ])
            throw USBIPProtocolError.unsupportedCommand(header.command.rawValue)
        }
    }
    
    /// Handle device list request with simulated devices
    private func handleSimulatedDeviceListRequest(_ data: Data) throws -> Data {
        logger.info("Handling simulated device list request")
        
        // Decode request (validation)
        _ = try DeviceListRequest.decode(from: data)
        
        // Get devices from simulator
        let devices = try deviceSimulator.discoverDevices()
        
        // Convert to USB/IP exported device format
        let exportedDevices = devices.map { device -> USBIPExportedDevice in
            USBIPExportedDevice(
                path: "/sys/devices/simulated/\(device.busID):\(device.deviceID)",
                busID: "\(device.busID):\(device.deviceID)",
                busnum: UInt32(Int(device.busID.split(separator: "-").first ?? "1") ?? 1),
                devnum: UInt32(Int(device.busID.split(separator: "-").last ?? "1") ?? 1),
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
        }
        
        // Create response
        let response = DeviceListResponse(devices: exportedDevices)
        
        logger.info("Sending simulated device list response", context: [
            "deviceCount": exportedDevices.count
        ])
        
        return try response.encode()
    }
    
    /// Handle device import request with simulated devices
    private func handleSimulatedDeviceImportRequest(_ data: Data) throws -> Data {
        logger.info("Handling simulated device import request")
        
        // Decode request
        let request = try DeviceImportRequest.decode(from: data)
        
        logger.info("Simulated device import request", context: [
            "busID": request.busID
        ])
        
        do {
            // Look for device using simulator
            guard let device = try deviceSimulator.getDeviceByUSBIPBusID(request.busID) else {
                logger.warning("Simulated device not found", context: [
                    "busID": request.busID
                ])
                
                let response = DeviceImportResponse(
                    header: USBIPHeader(command: .replyDeviceImport, status: 1),
                    returnCode: 1
                )
                return try response.encode()
            }
            
            // Try to claim the device
            let deviceIdentifier = "\(device.busID)-\(device.deviceID)"
            if deviceClaimManager.isDeviceClaimed(deviceID: deviceIdentifier) {
                logger.info("Simulated device already claimed", context: [
                    "deviceID": deviceIdentifier
                ])
            } else {
                let success = try deviceClaimManager.claimDevice(device)
                if !success {
                    logger.error("Failed to claim simulated device", context: [
                        "deviceID": deviceIdentifier
                    ])
                    
                    let response = DeviceImportResponse(
                        header: USBIPHeader(command: .replyDeviceImport, status: 1),
                        returnCode: 1
                    )
                    return try response.encode()
                }
                
                logger.info("Successfully claimed simulated device", context: [
                    "deviceID": deviceIdentifier
                ])
            }
            
            // Success response
            let response = DeviceImportResponse(returnCode: 0)
            logger.info("Simulated device import successful", context: [
                "busID": request.busID,
                "product": device.productString ?? "Unknown"
            ])
            
            return try response.encode()
            
        } catch {
            logger.error("Error in simulated device import", context: [
                "error": error.localizedDescription
            ])
            
            let response = DeviceImportResponse(
                header: USBIPHeader(command: .replyDeviceImport, status: 1),
                returnCode: 1
            )
            return try response.encode()
        }
    }
    
    /// Get simulator instance for testing
    public func getSimulator() -> TestDeviceSimulator {
        return deviceSimulator
    }
}