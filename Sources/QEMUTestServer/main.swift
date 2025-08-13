// main.swift
// QEMU Test Server - USB/IP test server for validation

import Foundation
import Common
import USBIPDCore

/// QEMU Test Server main entry point
class QEMUTestServer {
    private let logger: Logger
    private var server: TCPServer?
    private var requestProcessor: TestRequestProcessor?
    
    init(verbose: Bool = false) {
        let logLevel: LogLevel = verbose ? .debug : .info
        self.logger = Logger(
            config: LoggerConfig(level: logLevel, includeTimestamp: true),
            subsystem: "com.usbipd.qemu",
            category: "test-server"
        )
    }
    
    /// Run the test server
    func run() throws {
        logger.info("Starting QEMU Test Server")
        
        // Parse command line arguments
        let arguments = parseArguments()
        
        // Create test request processor
        requestProcessor = TestRequestProcessor(logger: logger)
        
        // Create and configure TCP server
        server = TCPServer()
        
        server?.onClientConnected = { [weak self] client in
            self?.logger.info("Client connected", context: [
                "clientId": client.id.uuidString
            ])
            self?.handleClientConnection(client)
        }
        
        server?.onClientDisconnected = { [weak self] client in
            self?.logger.info("Client disconnected", context: [
                "clientId": client.id.uuidString
            ])
        }
        
        // Start the server
        do {
            try server?.start(port: arguments.port)
            logger.info("QEMU Test Server listening", context: [
                "port": arguments.port,
                "version": USBIPProtocol.version
            ])
            
            // Keep the server running
            RunLoop.main.run()
        } catch {
            logger.error("Failed to start server", context: [
                "error": error.localizedDescription,
                "port": arguments.port
            ])
            throw error
        }
    }
    
    /// Handle new client connections
    private func handleClientConnection(_ client: ClientConnection) {
        guard let processor = requestProcessor else {
            logger.error("Request processor not available")
            return
        }
        
        // Cast to concrete type to allow property assignment
        if let tcpClient = client as? TCPClientConnection {
            // Set up data reception handler
            tcpClient.onDataReceived = { [weak self] data in
                self?.logger.debug("Received data", context: [
                    "clientId": client.id.uuidString,
                    "dataSize": data.count
                ])
                
                do {
                    let response = try processor.processRequest(data)
                    try client.send(data: response)
                    self?.logger.debug("Response sent successfully", context: [
                        "clientId": client.id.uuidString,
                        "responseSize": response.count
                    ])
                } catch {
                    self?.logger.error("Failed to process/send request", context: [
                        "clientId": client.id.uuidString,
                        "error": error.localizedDescription
                    ])
                }
            }
            
            tcpClient.onError = { [weak self] error in
                self?.logger.error("Client connection error", context: [
                    "clientId": client.id.uuidString,
                    "error": error.localizedDescription
                ])
            }
        } else {
            logger.error("Client is not a TCPClientConnection")
        }
    }
    
    /// Parse command line arguments
    private func parseArguments() -> ServerArguments {
        let args = CommandLine.arguments
        var port = 3240 // Default USB/IP port
        var verbose = false
        
        var i = 1
        while i < args.count {
            switch args[i] {
            case "--port", "-p":
                if i + 1 < args.count {
                    port = Int(args[i + 1]) ?? 3240
                    i += 1
                }
            case "--verbose", "-v":
                verbose = true
            case "--help", "-h":
                printUsage()
                exit(0)
            default:
                break
            }
            i += 1
        }
        
        // Note: Verbose mode is handled in init()
        
        return ServerArguments(port: port, verbose: verbose)
    }
    
    /// Print usage information
    private func printUsage() {
        print("QEMU Test Server - USB/IP protocol test server")
        print("Usage: QEMUTestServer [options]")
        print("")
        print("Options:")
        print("  -p, --port <port>    Listen port (default: 3240)")
        print("  -v, --verbose        Enable verbose logging")
        print("  -h, --help           Show this help message")
        print("")
        print("This server provides simulated USB/IP devices for testing purposes.")
    }
}

/// Server command line arguments
struct ServerArguments {
    let port: Int
    let verbose: Bool
}

/// Test request processor for handling USB/IP protocol messages
class TestRequestProcessor {
    private let logger: Logger
    private let testDevices: [USBIPExportedDevice]
    
    init(logger: Logger) {
        self.logger = logger
        
        // Create some test devices for simulation
        self.testDevices = [
            USBIPExportedDevice(
                path: "/sys/devices/test/1-1:1.0",
                busID: "1-1:1.0",
                busnum: 1,
                devnum: 2,
                speed: 2, // Full speed
                vendorID: 0x1234,
                productID: 0x5678,
                deviceClass: 3, // HID
                deviceSubClass: 1,
                deviceProtocol: 1,
                configurationCount: 1,
                configurationValue: 1,
                interfaceCount: 1
            ),
            USBIPExportedDevice(
                path: "/sys/devices/test/1-2:1.0",
                busID: "1-2:1.0",
                busnum: 1,
                devnum: 3,
                speed: 3, // High speed
                vendorID: 0xABCD,
                productID: 0xEF00,
                deviceClass: 9, // Hub
                deviceSubClass: 0,
                deviceProtocol: 0,
                configurationCount: 1,
                configurationValue: 1,
                interfaceCount: 1
            )
        ]
    }
    
    /// Process incoming USB/IP request and return response
    func processRequest(_ data: Data) throws -> Data {
        logger.debug("Processing USB/IP request", context: [
            "dataSize": data.count
        ])
        
        // Parse the header to determine request type
        guard data.count >= 8 else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        let header = try USBIPHeader.decode(from: data)
        logger.info("Processing request", context: [
            "command": String(format: "0x%04x", header.command.rawValue),
            "status": header.status
        ])
        
        switch header.command {
        case .requestDeviceList:
            return try handleDeviceListRequest(data)
            
        case .requestDeviceImport:
            return try handleDeviceImportRequest(data)
            
        case .submitRequest:
            logger.warning("USB SUBMIT request not implemented in test server")
            throw USBIPProtocolError.unsupportedCommand(header.command.rawValue)
            
        case .unlinkRequest:
            logger.warning("USB UNLINK request not implemented in test server")
            throw USBIPProtocolError.unsupportedCommand(header.command.rawValue)
            
        default:
            logger.error("Unsupported command", context: [
                "command": String(format: "0x%04x", header.command.rawValue)
            ])
            throw USBIPProtocolError.unsupportedCommand(header.command.rawValue)
        }
    }
    
    /// Handle device list request
    private func handleDeviceListRequest(_ data: Data) throws -> Data {
        logger.info("Handling device list request")
        
        // Decode request (validation)
        _ = try DeviceListRequest.decode(from: data)
        
        // Create response with test devices
        let response = DeviceListResponse(devices: testDevices)
        
        logger.info("Sending device list response", context: [
            "deviceCount": testDevices.count
        ])
        
        for (index, device) in testDevices.enumerated() {
            logger.debug("Test device", context: [
                "index": index,
                "busID": device.busID,
                "vendorID": String(format: "0x%04x", device.vendorID),
                "productID": String(format: "0x%04x", device.productID),
                "deviceClass": device.deviceClass
            ])
        }
        
        return try response.encode()
    }
    
    /// Handle device import request
    private func handleDeviceImportRequest(_ data: Data) throws -> Data {
        logger.info("Handling device import request")
        
        // Decode request
        let request = try DeviceImportRequest.decode(from: data)
        
        logger.info("Device import request", context: [
            "busID": request.busID
        ])
        
        // Check if the requested device exists in our test devices
        let deviceExists = testDevices.contains { $0.busID == request.busID }
        
        let response: DeviceImportResponse
        if deviceExists {
            logger.info("Device found, allowing import", context: [
                "busID": request.busID
            ])
            response = DeviceImportResponse(returnCode: 0) // Success
        } else {
            logger.warning("Device not found", context: [
                "busID": request.busID
            ])
            response = DeviceImportResponse(
                header: USBIPHeader(command: .replyDeviceImport, status: 1),
                returnCode: 1
            ) // Error
        }
        
        return try response.encode()
    }
}

// MARK: - Main Entry Point

do {
    // Parse arguments first to get verbose flag
    let args = CommandLine.arguments
    var verbose = false
    
    for i in 1..<args.count {
        if args[i] == "--verbose" || args[i] == "-v" {
            verbose = true
            break
        }
    }
    
    let server = QEMUTestServer(verbose: verbose)
    try server.run()
} catch {
    fputs("Fatal error: \(error.localizedDescription)\n", stderr)
    exit(1)
}