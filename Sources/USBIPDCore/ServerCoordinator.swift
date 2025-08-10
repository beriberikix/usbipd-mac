// ServerCoordinator.swift
// Core server coordinator for USB/IP server

import Foundation
import Common
import SystemExtensions

/// Extension for DateFormatter to provide consistent log formatting
extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}

/// System Extension lifecycle status information
public struct SystemExtensionLifecycleStatus {
    public let enabled: Bool
    public let state: String
    public let health: String?
    
    public init(enabled: Bool, state: String, health: String? = nil) {
        self.enabled = enabled
        self.state = state
        self.health = health
    }
}

/// Server coordinator that implements the USBIPServer protocol
public class ServerCoordinator: USBIPServer {
    /// Network service for handling client connections
    private var networkService: NetworkService
    
    /// Device discovery for USB device enumeration
    private var deviceDiscovery: DeviceDiscovery
    
    /// Request processor for handling USB/IP protocol requests
    private let requestProcessor: RequestProcessor
    
    /// Device claim manager for device claiming
    private let deviceClaimManager: DeviceClaimManager
    
    /// Server configuration
    private let config: ServerConfig
    
    /// Logger instance for server events
    private let logger: Logger
    
    /// Flag indicating if the server is running
    private var isServerRunning = false
    
    /// System Extension installer for managing System Extension lifecycle
    private let systemExtensionInstaller: SystemExtensionInstaller?
    
    /// System Extension lifecycle manager for health monitoring and management
    private let systemExtensionLifecycleManager: SystemExtensionLifecycleManager?
    
    /// Flag indicating if System Extension management is enabled
    private let systemExtensionEnabled: Bool
    
    /// Callback for error events
    public var onError: ((Error) -> Void)?
    
    /// Initialize with network service, device discovery, and optional device claim manager
    public init(networkService: NetworkService, 
               deviceDiscovery: DeviceDiscovery, 
               deviceClaimManager: DeviceClaimManager? = nil, 
               config: ServerConfig = ServerConfig(),
               systemExtensionBundlePath: String? = nil,
               systemExtensionBundleIdentifier: String? = nil) {
        self.networkService = networkService
        self.deviceDiscovery = deviceDiscovery
        self.config = config
        
        // Initialize System Extension components if paths are provided
        if let bundlePath = systemExtensionBundlePath,
           let bundleIdentifier = systemExtensionBundleIdentifier {
            self.systemExtensionEnabled = true
            self.systemExtensionInstaller = SystemExtensionInstaller(
                bundleIdentifier: bundleIdentifier,
                bundlePath: bundlePath
            )
            self.systemExtensionLifecycleManager = SystemExtensionLifecycleManager(
                installer: self.systemExtensionInstaller!,
                healthConfig: SystemExtensionLifecycleManager.HealthConfig()
            )
        } else {
            self.systemExtensionEnabled = false
            self.systemExtensionInstaller = nil
            self.systemExtensionLifecycleManager = nil
        }
        
        // Initialize logger with appropriate configuration
        let loggerConfig = LoggerConfig(
            level: config.logLevel,
            includeTimestamp: true,
            includeContext: config.debugMode
        )
        self.logger = Logger(config: loggerConfig, subsystem: "com.usbipd.mac", category: "server")
        
        // Use provided device claim manager or create a mock one
        self.deviceClaimManager = deviceClaimManager ?? MockDeviceClaimManager()
        
        // Create request processor with device claim manager and configurable logging
        self.requestProcessor = RequestProcessor(
            deviceDiscovery: deviceDiscovery, 
            deviceClaimManager: self.deviceClaimManager
        ) { [weak config] message, processorLevel in
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
        setupSystemExtensionCallbacks()
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
    
    /// Set up System Extension lifecycle callbacks
    private func setupSystemExtensionCallbacks() {
        guard systemExtensionEnabled,
              let lifecycleManager = systemExtensionLifecycleManager else {
            logger.debug("System Extension management disabled")
            return
        }
        
        // Set up lifecycle delegate
        lifecycleManager.delegate = self
        
        logger.info("System Extension lifecycle callbacks configured")
    }
    
    /// Activate System Extension if enabled
    private func activateSystemExtension() throws {
        guard let lifecycleManager = systemExtensionLifecycleManager else {
            throw ServerError.initializationFailed("System Extension lifecycle manager not initialized")
        }
        
        logger.info("Activating System Extension")
        
        // Create a semaphore to wait for activation completion
        let semaphore = DispatchSemaphore(value: 0)
        var activationError: SystemExtensionInstallationError?
        
        lifecycleManager.activate { result in
            switch result {
            case .success:
                break // Success, no error
            case .failure(let error):
                activationError = error
            }
            semaphore.signal()
        }
        
        // Wait for activation to complete (with timeout)
        let timeoutResult = semaphore.wait(timeout: .now() + 30) // 30 second timeout
        
        if timeoutResult == .timedOut {
            throw ServerError.initializationFailed("System Extension activation timed out")
        }
        
        if let error = activationError {
            logger.error("System Extension activation failed", context: ["error": error.localizedDescription])
            
            // Handle specific errors that might require user intervention
            switch error {
            case .requiresApproval:
                logger.info("System Extension requires user approval in System Preferences")
                // Continue with server startup - System Extension will be available once approved
            case .userRejected:
                throw ServerError.initializationFailed("System Extension installation was rejected by user")
            default:
                throw ServerError.initializationFailed("System Extension activation failed: \(error.localizedDescription)")
            }
        }
        
        logger.info("System Extension activation completed")
    }
    
    /// Check System Extension status before device operations
    private func checkSystemExtensionStatus() throws {
        guard systemExtensionEnabled,
              let lifecycleManager = systemExtensionLifecycleManager else {
            return // System Extension not enabled, skip check
        }
        
        let state = lifecycleManager.state
        
        switch state {
        case .active:
            // System Extension is active, all good
            break
        case .failed(let error):
            logger.error("System Extension failed", context: ["error": error])
            throw ServerError.systemExtensionFailed("System Extension failed: \(error)")
        case .inactive:
            logger.warning("System Extension is not active")
            throw ServerError.systemExtensionFailed("System Extension is not active")
        case .activating:
            logger.info("System Extension is still activating")
            // Could wait or continue with limited functionality
        case .deactivating:
            logger.warning("System Extension is deactivating")
            throw ServerError.systemExtensionFailed("System Extension is deactivating")
        case let .upgrading(from, to):
            logger.info("System Extension is upgrading", context: ["from": from, "to": to])
            // Could wait for upgrade completion
        case .requiresReboot:
            logger.warning("System Extension requires system reboot")
            throw ServerError.systemExtensionFailed("System Extension requires system reboot")
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
            
            // Device claim manager is already initialized and ready
            
            // Activate System Extension if enabled
            if systemExtensionEnabled {
                try activateSystemExtension()
            }
            
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
        
        // Deactivate System Extension if enabled
        if systemExtensionEnabled {
            deactivateSystemExtension()
        }
        
        // Device claim manager cleanup (if needed) would happen in its own deinit
        
        isServerRunning = false
    }
    
    /// Deactivate System Extension if enabled
    private func deactivateSystemExtension() {
        guard let lifecycleManager = systemExtensionLifecycleManager else {
            return
        }
        
        logger.info("Deactivating System Extension")
        
        // Deactivate asynchronously - don't block server shutdown
        lifecycleManager.deactivate { result in
            switch result {
            case .success:
                self.logger.info("System Extension deactivated successfully")
            case .failure(let error):
                self.logger.error("System Extension deactivation failed", context: ["error": error.localizedDescription])
                // Don't throw error during shutdown - just log it
            }
        }
    }
    
    /// Check if the server is running
    public func isRunning() -> Bool {
        return isServerRunning
    }
    
    /// Get System Extension status information
    public func getSystemExtensionStatus() -> SystemExtensionLifecycleStatus {
        guard systemExtensionEnabled,
              let lifecycleManager = systemExtensionLifecycleManager else {
            return SystemExtensionLifecycleStatus(enabled: false, state: "disabled", health: nil)
        }
        
        let stateDescription: String
        switch lifecycleManager.state {
        case .inactive:
            stateDescription = "inactive"
        case .activating:
            stateDescription = "activating"
        case .active:
            stateDescription = "active"
        case .deactivating:
            stateDescription = "deactivating"
        case .failed(let error):
            stateDescription = "failed: \(error)"
        case let .upgrading(from, to):
            stateDescription = "upgrading from \(from) to \(to)"
        case .requiresReboot:
            stateDescription = "requires reboot"
        }
        
        let healthStatus = lifecycleManager.healthStatus
        let healthDescription = "healthy: \(healthStatus.isHealthy), failures: \(healthStatus.consecutiveFailures), uptime: \(Int(healthStatus.uptime))s"
        
        return SystemExtensionLifecycleStatus(enabled: true, state: stateDescription, health: healthDescription)
    }
}

// MARK: - SystemExtensionLifecycleDelegate

extension ServerCoordinator: SystemExtensionLifecycleDelegate {
    public func lifecycleManager(_ manager: SystemExtensionLifecycleManager,
                               didChangeState oldState: SystemExtensionLifecycleManager.LifecycleState,
                               to newState: SystemExtensionLifecycleManager.LifecycleState) {
        
        logger.info("System Extension state changed", context: [
            "from": String(describing: oldState),
            "to": String(describing: newState)
        ])
        
        // Handle state changes that might affect server operations
        switch newState {
        case .active:
            logger.info("System Extension is now active and ready for device operations")
            
        case .failed(let error):
            logger.error("System Extension failed", context: ["error": error])
            onError?(ServerError.systemExtensionFailed(error))
            
        case .requiresReboot:
            logger.warning("System Extension requires system reboot to complete installation")
            
        default:
            break // Other states are handled by logging above
        }
    }
    
    public func lifecycleManager(_ manager: SystemExtensionLifecycleManager,
                               didUpdateHealth healthStatus: SystemExtensionLifecycleManager.HealthStatus) {
        
        if !healthStatus.isHealthy {
            logger.warning("System Extension health check failed", context: [
                "consecutiveFailures": healthStatus.consecutiveFailures,
                "lastError": healthStatus.lastError ?? "unknown",
                "uptime": healthStatus.uptime
            ])
        } else {
            logger.debug("System Extension health check passed", context: [
                "uptime": healthStatus.uptime,
                "restartCount": healthStatus.restartCount
            ])
        }
        
        // Log restart events
        if healthStatus.restartCount > 0 {
            logger.info("System Extension has been restarted", context: [
                "restartCount": healthStatus.restartCount
            ])
        }
    }
}