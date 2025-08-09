// IPCHandler.swift
// Secure inter-process communication between daemon and System Extension

import Foundation
import XPC
import Common

// MARK: - IPC Handler Protocol

/// Protocol for handling IPC communication between daemon and System Extension
public protocol IPCHandler {
    /// Start listening for IPC requests
    /// - Throws: SystemExtensionError if listener setup fails
    func startListener() throws
    
    /// Stop listening for IPC requests
    func stopListener()
    
    /// Send a response to an IPC request
    /// - Parameters:
    ///   - request: Original IPC request
    ///   - response: Response to send back
    /// - Throws: SystemExtensionError if response fails to send
    func sendResponse(to request: IPCRequest, response: IPCResponse) throws
    
    /// Check if a client is authenticated and authorized
    /// - Parameter clientID: Client identifier to authenticate
    /// - Returns: True if client is authenticated, false otherwise
    func authenticateClient(clientID: String) -> Bool
    
    /// Get current listener status
    /// - Returns: True if listener is active, false otherwise
    func isListening() -> Bool
    
    /// Get IPC statistics for monitoring
    /// - Returns: Current IPC statistics
    func getStatistics() -> IPCStatistics
}

// MARK: - XPC-Based IPC Handler Implementation

/// XPC-based implementation of IPC communication for System Extension
public class XPCIPCHandler: NSObject, IPCHandler {
    
    // MARK: - Properties
    
    /// XPC listener for incoming connections
    private var listener: NSXPCListener?
    
    /// Active XPC connections (clientID -> connection)
    private var activeConnections: [String: NSXPCConnection] = [:]
    
    /// Pending requests waiting for responses (requestID -> connection)
    private var pendingRequests: [UUID: NSXPCConnection] = [:]
    
    /// Logger for IPC operations
    private let logger: Logger
    
    /// Queue for serializing IPC operations
    private let queue: DispatchQueue
    
    /// Configuration for IPC behavior
    private let config: IPCConfiguration
    
    /// Request timeout timer
    private var timeoutTimer: DispatchSourceTimer?
    
    /// IPC statistics tracking
    private var statistics: IPCStatistics
    
    /// Authentication manager
    private let authManager: IPCAuthenticationManager
    
    /// JSON encoder/decoder for message serialization
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    
    // MARK: - Initialization
    
    /// Initialize XPC IPC handler with default configuration  
    public convenience override init() {
        let logger = Logger(
            config: LoggerConfig(level: .info),
            subsystem: "com.usbipd.mac.system-extension",
            category: "ipc"
        )
        
        self.init(
            config: IPCConfiguration(),
            logger: logger,
            authManager: DefaultIPCAuthenticationManager()
        )
    }
    
    /// Initialize with custom configuration for testing
    /// - Parameters:
    ///   - config: IPC configuration
    ///   - logger: Logger instance
    ///   - authManager: Authentication manager
    public init(config: IPCConfiguration, logger: Logger, authManager: IPCAuthenticationManager) {
        self.config = config
        self.logger = logger
        self.authManager = authManager
        self.queue = DispatchQueue(
            label: "com.usbipd.mac.system-extension.ipc",
            qos: .userInitiated
        )
        self.statistics = IPCStatistics()
        
        super.init()
        
        // Configure JSON encoder/decoder after super.init
        setupJSONCoding()
        
        logger.info("XPCIPCHandler initialized", context: [
            "serviceName": config.serviceName,
            "maxConnections": config.maxConnections,
            "requestTimeout": config.requestTimeout
        ])
    }
    
    deinit {
        stopListener()
        logger.info("XPCIPCHandler deinitialized", context: [
            "handledRequests": statistics.totalRequests,
            "activeConnections": activeConnections.count
        ])
    }
    
    // MARK: - IPCHandler Protocol Implementation
    
    public func startListener() throws {
        try queue.sync {
            guard listener == nil else {
                logger.warning("IPC listener already started")
                return
            }
            
            logger.info("Starting XPC listener", context: ["serviceName": config.serviceName])
            
            // Create XPC listener
            listener = NSXPCListener(machServiceName: config.serviceName)
            listener?.delegate = self
            
            // Start accepting connections
            listener?.resume()
            
            // Set up timeout timer for cleaning up stale requests
            setupTimeoutTimer()
            
            statistics.startTime = Date()
            logger.info("XPC listener started successfully")
        }
    }
    
    public func stopListener() {
        queue.sync {
            guard let listener = listener else {
                logger.debug("IPC listener not running")
                return
            }
            
            logger.info("Stopping XPC listener", context: [
                "activeConnections": activeConnections.count,
                "pendingRequests": pendingRequests.count
            ])
            
            // Stop accepting new connections
            listener.suspend()
            
            // Clean up active connections
            for (clientID, connection) in activeConnections {
                logger.debug("Invalidating connection for client", context: ["clientID": clientID])
                connection.invalidate()
            }
            activeConnections.removeAll()
            pendingRequests.removeAll()
            
            // Stop timeout timer
            timeoutTimer?.cancel()
            timeoutTimer = nil
            
            self.listener = nil
            statistics.stopTime = Date()
            
            logger.info("XPC listener stopped")
        }
    }
    
    public func sendResponse(to request: IPCRequest, response: IPCResponse) throws {
        try queue.sync {
            let startTime = Date()
            
            logger.debug("Sending IPC response", context: [
                "requestID": request.requestID.uuidString,
                "clientID": request.clientID,
                "success": response.success
            ])
            
            // Find connection for this request
            guard let connection = pendingRequests[request.requestID] else {
                logger.error("No active connection for request", context: [
                    "requestID": request.requestID.uuidString
                ])
                throw SystemExtensionError.ipcError("Connection not found for request \(request.requestID)")
            }
            
            do {
                // Serialize response
                let responseData = try jsonEncoder.encode(response)
                
                // Send response via XPC
                try sendXPCResponse(connection: connection, data: responseData)
                
                // Clean up pending request
                pendingRequests.removeValue(forKey: request.requestID)
                
                // Update statistics
                let duration = Date().timeIntervalSince(startTime) * 1000 // milliseconds
                statistics.recordResponse(success: response.success, duration: duration)
                
                logger.debug("IPC response sent successfully", context: [
                    "requestID": request.requestID.uuidString,
                    "responseSize": responseData.count,
                    "duration": String(format: "%.2f", duration)
                ])
                
            } catch {
                statistics.recordResponse(success: false, duration: 0)
                logger.error("Failed to send IPC response", context: [
                    "requestID": request.requestID.uuidString,
                    "error": error.localizedDescription
                ])
                throw SystemExtensionError.ipcError("Failed to send response: \(error.localizedDescription)")
            }
        }
    }
    
    public func authenticateClient(clientID: String) -> Bool {
        return queue.sync {
            let isAuthenticated = authManager.authenticateClient(clientID: clientID)
            
            logger.debug("Client authentication", context: [
                "clientID": clientID,
                "authenticated": isAuthenticated
            ])
            
            if isAuthenticated {
                statistics.authenticatedClients += 1
            } else {
                statistics.authenticationFailures += 1
            }
            
            return isAuthenticated
        }
    }
    
    public func isListening() -> Bool {
        return queue.sync {
            return listener != nil
        }
    }
    
    public func getStatistics() -> IPCStatistics {
        return queue.sync {
            return statistics
        }
    }
    
    // MARK: - Private Implementation
    
    private func setupJSONCoding() {
        // Configure JSON encoder for consistent output
        jsonEncoder.dateEncodingStrategy = .iso8601
        jsonEncoder.outputFormatting = .prettyPrinted
        
        // Configure JSON decoder to handle dates
        jsonDecoder.dateDecodingStrategy = .iso8601
    }
    
    private func setupTimeoutTimer() {
        timeoutTimer = DispatchSource.makeTimerSource(queue: queue)
        timeoutTimer?.schedule(deadline: .now() + .seconds(Int(config.requestTimeout)), repeating: .seconds(Int(config.requestTimeout)))
        
        timeoutTimer?.setEventHandler { [weak self] in
            self?.cleanupTimedOutRequests()
        }
        
        timeoutTimer?.resume()
    }
    
    private func cleanupTimedOutRequests() {
        let now = Date()
        let timeout = config.requestTimeout
        
        var timedOutRequests: [UUID] = []
        
        for (requestID, _) in pendingRequests {
            // In a real implementation, we would track request timestamps
            // For now, we'll clean up requests that have been pending too long
            // This is a simplified timeout mechanism
            if pendingRequests.count > config.maxPendingRequests {
                timedOutRequests.append(requestID)
            }
        }
        
        for requestID in timedOutRequests {
            logger.warning("Cleaning up timed out request", context: [
                "requestID": requestID.uuidString
            ])
            pendingRequests.removeValue(forKey: requestID)
            statistics.timeouts += 1
        }
        
        if !timedOutRequests.isEmpty {
            logger.info("Cleaned up timed out requests", context: [
                "count": timedOutRequests.count
            ])
        }
    }
    
    private func sendXPCResponse(connection: NSXPCConnection, data: Data) throws {
        // In a real XPC implementation, we would use XPC dictionaries and proper serialization
        // For this MVP, we simulate the XPC response mechanism
        
        logger.debug("Sending XPC response", context: [
            "dataSize": data.count,
            "connectionPID": connection.processIdentifier
        ])
        
        // Simulate XPC response (in real implementation, this would use xpc_dictionary_create, etc.)
        // For MVP, we'll assume the response is successfully sent
        
        if data.count > config.maxMessageSize {
            throw SystemExtensionError.ipcError("Response too large: \(data.count) bytes")
        }
        
        // Simulate network delay for testing
        if config.simulateNetworkDelay > 0 {
            Thread.sleep(forTimeInterval: config.simulateNetworkDelay)
        }
    }
    
    private func handleIncomingRequest(_ requestData: Data, from connection: NSXPCConnection) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Deserialize request
                let request = try self.jsonDecoder.decode(IPCRequest.self, from: requestData)
                
                self.logger.debug("Received IPC request", context: [
                    "requestID": request.requestID.uuidString,
                    "clientID": request.clientID,
                    "command": request.command.rawValue,
                    "dataSize": requestData.count
                ])
                
                // Authenticate client
                guard self.authenticateClient(clientID: request.clientID) else {
                    let errorResponse = IPCResponse(
                        requestID: request.requestID,
                        success: false,
                        error: SystemExtensionError.authenticationFailed("Client not authenticated: \(request.clientID)")
                    )
                    
                    try self.sendResponse(to: request, response: errorResponse)
                    return
                }
                
                // Store pending request
                self.pendingRequests[request.requestID] = connection
                
                // Update statistics
                self.statistics.recordRequest(command: request.command)
                
                // Delegate request handling to the System Extension manager
                self.notifyRequestReceived(request)
                
            } catch {
                self.logger.error("Failed to handle incoming IPC request", context: [
                    "error": error.localizedDescription
                ])
                
                self.statistics.invalidRequests += 1
            }
        }
    }
    
    private func notifyRequestReceived(_ request: IPCRequest) {
        // In a real implementation, this would notify the SystemExtensionManager
        // For now, we'll simulate the notification mechanism
        
        logger.info("Notifying System Extension manager of request", context: [
            "requestID": request.requestID.uuidString,
            "command": request.command.rawValue
        ])
        
        // This would typically use a delegate pattern or callback mechanism
        // to notify the SystemExtensionManager that a request was received
    }
}

// MARK: - NSXPCListenerDelegate

extension XPCIPCHandler: NSXPCListenerDelegate {
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        return queue.sync {
            logger.info("New XPC connection request", context: [
                "pid": newConnection.processIdentifier,
                "activeConnections": activeConnections.count,
                "maxConnections": config.maxConnections
            ])
            
            // Check connection limits
            guard activeConnections.count < config.maxConnections else {
                logger.warning("Rejecting connection - maximum connections reached", context: [
                    "maxConnections": config.maxConnections
                ])
                statistics.rejectedConnections += 1
                return false
            }
            
            // Generate client ID based on process identifier
            let clientID = "client-\(newConnection.processIdentifier)"
            
            // Set up connection
            setupXPCConnection(newConnection, clientID: clientID)
            
            // Store active connection
            activeConnections[clientID] = newConnection
            statistics.acceptedConnections += 1
            
            logger.info("Accepted new XPC connection", context: [
                "clientID": clientID,
                "totalConnections": activeConnections.count
            ])
            
            return true
        }
    }
    
    private func setupXPCConnection(_ connection: NSXPCConnection, clientID: String) {
        // Set up connection handlers
        connection.invalidationHandler = { [weak self] in
            self?.handleConnectionInvalidation(clientID: clientID)
        }
        
        connection.interruptionHandler = { [weak self] in
            self?.handleConnectionInterruption(clientID: clientID)
        }
        
        // Resume connection to start processing
        connection.resume()
        
        logger.debug("XPC connection setup complete", context: ["clientID": clientID])
    }
    
    private func handleConnectionInvalidation(clientID: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            self.logger.info("XPC connection invalidated", context: ["clientID": clientID])
            
            // Clean up connection
            self.activeConnections.removeValue(forKey: clientID)
            
            // Clean up any pending requests for this client
            let requestsToRemove = self.pendingRequests.filter { _, connection in
                connection.processIdentifier.description.contains(clientID.replacingOccurrences(of: "client-", with: ""))
            }
            
            for (requestID, _) in requestsToRemove {
                self.pendingRequests.removeValue(forKey: requestID)
                self.logger.debug("Cleaned up pending request for invalidated connection", context: [
                    "requestID": requestID.uuidString,
                    "clientID": clientID
                ])
            }
            
            self.statistics.disconnectedClients += 1
        }
    }
    
    private func handleConnectionInterruption(clientID: String) {
        logger.warning("XPC connection interrupted", context: ["clientID": clientID])
        statistics.connectionInterruptions += 1
    }
}

// MARK: - Configuration and Supporting Types

/// Configuration for IPC handler behavior
public struct IPCConfiguration {
    /// XPC service name for the System Extension
    public let serviceName: String
    
    /// Maximum number of concurrent connections
    public let maxConnections: Int
    
    /// Request timeout in seconds
    public let requestTimeout: TimeInterval
    
    /// Maximum pending requests before cleanup
    public let maxPendingRequests: Int
    
    /// Maximum message size in bytes
    public let maxMessageSize: Int
    
    /// Simulated network delay for testing (seconds)
    public let simulateNetworkDelay: TimeInterval
    
    public init(
        serviceName: String = "com.usbipd.mac.system-extension",
        maxConnections: Int = 10,
        requestTimeout: TimeInterval = 30.0,
        maxPendingRequests: Int = 100,
        maxMessageSize: Int = 1024 * 1024, // 1MB
        simulateNetworkDelay: TimeInterval = 0.0
    ) {
        self.serviceName = serviceName
        self.maxConnections = maxConnections
        self.requestTimeout = requestTimeout
        self.maxPendingRequests = maxPendingRequests
        self.maxMessageSize = maxMessageSize
        self.simulateNetworkDelay = simulateNetworkDelay
    }
}

/// Statistics for IPC operations
public struct IPCStatistics {
    /// When the IPC handler was started
    public var startTime: Date?
    
    /// When the IPC handler was stopped
    public var stopTime: Date?
    
    /// Total number of requests received
    public var totalRequests: Int = 0
    
    /// Total number of responses sent
    public var totalResponses: Int = 0
    
    /// Number of successful responses
    public var successfulResponses: Int = 0
    
    /// Number of failed responses
    public var failedResponses: Int = 0
    
    /// Number of accepted connections
    public var acceptedConnections: Int = 0
    
    /// Number of rejected connections
    public var rejectedConnections: Int = 0
    
    /// Number of disconnected clients
    public var disconnectedClients: Int = 0
    
    /// Number of connection interruptions
    public var connectionInterruptions: Int = 0
    
    /// Number of authenticated clients
    public var authenticatedClients: Int = 0
    
    /// Number of authentication failures
    public var authenticationFailures: Int = 0
    
    /// Number of timed out requests
    public var timeouts: Int = 0
    
    /// Number of invalid requests
    public var invalidRequests: Int = 0
    
    /// Request counts by command type
    public var requestsByCommand: [IPCCommand: Int] = [:]
    
    /// Average response time in milliseconds
    public var averageResponseTime: Double = 0.0
    
    /// Total response time for calculating averages
    private var totalResponseTime: Double = 0.0
    
    public init() {}
    
    /// Record a new request
    mutating func recordRequest(command: IPCCommand) {
        totalRequests += 1
        requestsByCommand[command, default: 0] += 1
    }
    
    /// Record a response
    mutating func recordResponse(success: Bool, duration: Double) {
        totalResponses += 1
        totalResponseTime += duration
        averageResponseTime = totalResponseTime / Double(totalResponses)
        
        if success {
            successfulResponses += 1
        } else {
            failedResponses += 1
        }
    }
    
    /// Get success rate as percentage
    public var successRate: Double {
        return totalResponses > 0 ? Double(successfulResponses) / Double(totalResponses) * 100.0 : 0.0
    }
    
    /// Get uptime in seconds
    public var uptime: TimeInterval {
        if let startTime = startTime {
            return (stopTime ?? Date()).timeIntervalSince(startTime)
        }
        return 0.0
    }
}

// MARK: - Authentication Manager

/// Protocol for IPC client authentication
public protocol IPCAuthenticationManager {
    /// Authenticate a client by ID
    /// - Parameter clientID: Client identifier to authenticate
    /// - Returns: True if client is authorized, false otherwise
    func authenticateClient(clientID: String) -> Bool
}

/// Default implementation of IPC authentication
public class DefaultIPCAuthenticationManager: IPCAuthenticationManager {
    /// Set of authorized client IDs
    private var authorizedClients: Set<String> = []
    
    /// Logger for authentication events
    private let logger: Logger
    
    public init() {
        self.logger = Logger(
            config: LoggerConfig(level: .info),
            subsystem: "com.usbipd.mac.system-extension",
            category: "auth"
        )
        
        // For MVP, allow all clients (in production, this would be more restrictive)
        setupDefaultAuthorization()
    }
    
    public func authenticateClient(clientID: String) -> Bool {
        // For MVP, perform basic validation
        let isValid = !clientID.isEmpty && clientID.hasPrefix("client-")
        
        if isValid {
            logger.debug("Client authenticated", context: ["clientID": clientID])
        } else {
            logger.warning("Client authentication failed", context: ["clientID": clientID])
        }
        
        return isValid
    }
    
    private func setupDefaultAuthorization() {
        // In a production system, this would load authorized clients from configuration
        // For MVP, we'll use a permissive approach
        logger.info("Default IPC authentication manager initialized")
    }
}