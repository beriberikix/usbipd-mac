// ServerCoordinator.swift
// Core server coordinator for USB/IP server

import Foundation
import Common

/// Extension for DateFormatter to provide consistent log formatting
extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}

/// Server coordinator that implements the USBIPServer protocol
public class ServerCoordinator: USBIPServer {
    /// Network service for handling client connections
    private var networkService: NetworkService
    
    /// Device discovery for USB device enumeration
    private var deviceDiscovery: DeviceDiscovery
    
    /// Request processor for handling USB/IP protocol requests
    private let requestProcessor: RequestProcessor
    
    /// Server configuration
    private let config: ServerConfig
    
    /// Logger instance for server events
    private let logger: Logger
    
    /// Flag indicating if the server is running
    private var isServerRunning = false
    
    /// Callback for error events
    public var onError: ((Error) -> Void)?
    
    /// Initialize with network service, device discovery, and configuration
    public init(networkService: NetworkService, deviceDiscovery: DeviceDiscovery, config: ServerConfig = ServerConfig()) {
        self.networkService = networkService
        self.deviceDiscovery = deviceDiscovery
        self.config = config
        
        // Initialize logger with appropriate configuration
        let loggerConfig = LoggerConfig(
            level: config.logLevel,
            includeTimestamp: true,
            includeContext: config.debugMode
        )
        self.logger = Logger(config: loggerConfig, subsystem: "com.usbipd.mac", category: "server")
        
        // Create request processor with configurable logging
        self.requestProcessor = RequestProcessor(deviceDiscovery: deviceDiscovery) { [weak config] message, processorLevel in
            guard let config = config else { return }
            
            // Convert RequestProcessor.LogLevel to ServerConfig.LogLevel
            let configLevel: LogLevel
            switch processorLevel {
            case .debug: configLevel = .debug
            case .info: configLevel = .info
            case .warning: configLevel = .warning
            case .error: configLevel = .error
            }
            
            // Check if we should log this message based on configured log level
            guard config.shouldLog(level: configLevel) else { return }
            
            let timestamp = DateFormatter.logFormatter.string(from: Date())
            let prefix: String
            switch processorLevel {
            case .debug: prefix = "[DEBUG]"
            case .info: prefix = "[INFO]"
            case .warning: prefix = "[WARNING]"
            case .error: prefix = "[ERROR]"
            }
            
            let logMessage = "\(timestamp) \(prefix) \(message)"
            
            // Log to file if configured
            if let logFilePath = config.logFilePath {
                do {
                    let fileHandle: FileHandle
                    if FileManager.default.fileExists(atPath: logFilePath) {
                        fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: logFilePath))
                        fileHandle.seekToEndOfFile()
                    } else {
                        FileManager.default.createFile(atPath: logFilePath, contents: nil)
                        fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: logFilePath))
                    }
                    
                    if let data = (logMessage + "\n").data(using: .utf8) {
                        fileHandle.write(data)
                    }
                    fileHandle.closeFile()
                } catch {
                    print("Error writing to log file: \(error.localizedDescription)")
                }
            }
            
            // Always print to console
            print(logMessage)
            
            // Include protocol-level details in debug mode
            if config.debugMode && processorLevel == .debug {
                // Additional debug information could be added here
            }
        }
        
        setupCallbacks()
    }
    
    /// Set up callbacks for network and device events
    private func setupCallbacks() {
        // Handle client connections
        networkService.onClientConnected = { [weak self] clientConnection in
            guard let self = self else { return }
            
            self.logger.info("Client connected", context: ["connectionId": clientConnection.id.uuidString])
            
            // Create a local mutable variable for the connection
            var connection = clientConnection
            
            // Set up data handler for the connection
            connection.onDataReceived = { [weak self] data in
                guard let self = self else { return }
                
                self.logger.debug("Received data from client", context: [
                    "connectionId": connection.id.uuidString,
                    "dataSize": data.count
                ])
                
                do {
                    // Process the request using the request processor
                    let responseData = try self.requestProcessor.processRequest(data)
                    
                    // Send the response back to the client
                    try connection.send(data: responseData)
                    
                    self.logger.debug("Sent response to client", context: [
                        "connectionId": connection.id.uuidString,
                        "responseSize": responseData.count
                    ])
                } catch {
                    self.logger.error("Failed to process request", context: [
                        "connectionId": connection.id.uuidString,
                        "error": error.localizedDescription
                    ])
                    
                    // Forward error to server error handler
                    self.onError?(error)
                    
                    // Close the connection on critical errors
                    if case USBIPProtocolError.invalidHeader = error {
                        self.logger.warning("Closing connection due to invalid header", context: [
                            "connectionId": connection.id.uuidString
                        ])
                        try? connection.close()
                    }
                }
            }
            
            // Set up error handler for the connection
            connection.onError = { [weak self] error in
                guard let self = self else { return }
                
                self.logger.error("Client connection error", context: [
                    "connectionId": connection.id.uuidString,
                    "error": error.localizedDescription
                ])
                
                // Forward error to server error handler
                self.onError?(error)
            }
        }
        
        // Handle client disconnections
        networkService.onClientDisconnected = { [weak self] clientConnection in
            guard let self = self else { return }
            
            self.logger.info("Client disconnected", context: ["connectionId": clientConnection.id.uuidString])
            // Clean up resources if needed
        }
        
        // Handle device connections
        deviceDiscovery.onDeviceConnected = { [weak self] device in
            guard let self = self else { return }
            
            self.logger.info("USB device connected", context: [
                "busID": device.busID,
                "deviceID": device.deviceID,
                "vendorID": String(format: "0x%04x", device.vendorID),
                "productID": String(format: "0x%04x", device.productID),
                "product": device.productString ?? "Unknown"
            ])
        }
        
        // Handle device disconnections
        deviceDiscovery.onDeviceDisconnected = { [weak self] device in
            guard let self = self else { return }
            
            self.logger.info("USB device disconnected", context: [
                "busID": device.busID,
                "deviceID": device.deviceID,
                "vendorID": String(format: "0x%04x", device.vendorID),
                "productID": String(format: "0x%04x", device.productID)
            ])
        }
    }
    
    /// Start the USB/IP server
    public func start() throws {
        guard !isServerRunning else {
            throw ServerError.alreadyRunning
        }
        
        do {
            // Validate configuration before starting
            try config.validate()
            
            // Log server startup
            let timestamp = DateFormatter.logFormatter.string(from: Date())
            print("\(timestamp) [INFO] Starting USB/IP server on port \(config.port)")
            
            // Start device discovery notifications
            try deviceDiscovery.startNotifications()
            
            // Start network service
            try networkService.start(port: config.port)
            
            isServerRunning = true
            
            // Log successful startup
            print("\(timestamp) [INFO] USB/IP server started successfully")
        } catch let configError as ServerError {
            // Forward configuration error
            throw configError
        } catch {
            // Clean up if any component fails to start
            deviceDiscovery.stopNotifications() // This method doesn't throw
            do {
                try networkService.stop()
            } catch {
                // Ignore errors during cleanup
            }
            
            // Forward error
            throw ServerError.initializationFailed("Failed to start server: \(error.localizedDescription)")
        }
    }
    
    /// Stop the USB/IP server
    public func stop() throws {
        guard isServerRunning else {
            throw ServerError.notRunning
        }
        
        // Stop device discovery notifications
        deviceDiscovery.stopNotifications()
        
        // Stop network service
        try networkService.stop()
        
        isServerRunning = false
    }
    
    /// Check if the server is running
    public func isRunning() -> Bool {
        return isServerRunning
    }
}