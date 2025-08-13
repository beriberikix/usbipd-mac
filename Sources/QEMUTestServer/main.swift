// main.swift
// QEMU Test Server - USB/IP test server for validation

import Foundation
import Common
import USBIPDCore

/// QEMU Test Server main entry point
class QEMUTestServer {
    private let logger: Logger
    private var server: TCPServer?
    private var requestProcessor: SimulatedTestRequestProcessor?
    
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
        
        // Create simulated test request processor
        requestProcessor = SimulatedTestRequestProcessor(logger: logger)
        
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