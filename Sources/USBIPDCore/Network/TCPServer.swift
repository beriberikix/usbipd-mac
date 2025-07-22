// TCPServer.swift
// TCP server implementation using Network.framework

import Foundation
import Network
import Common

/// TCP server implementation using Network.framework
public class TCPServer: NetworkService {
    private var listener: NWListener?
    private var connections: [UUID: TCPClientConnection] = [:]
    private let queue = DispatchQueue(label: "TCPServer", qos: .userInitiated)
    private var isListening = false
    private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "network")
    
    /// Callback for client connection events
    public var onClientConnected: ((ClientConnection) -> Void)?
    
    /// Callback for client disconnection events
    public var onClientDisconnected: ((ClientConnection) -> Void)?
    
    public init() {}
    
    /// Start the TCP server on the specified port
    public func start(port: Int) throws {
        guard !isListening else {
            logger.warning("Attempted to start TCP server that is already running")
            throw ServerError.alreadyRunning
        }
        
        logger.info("Starting TCP server", context: ["port": port])
        
        // Validate port range
        guard port > 0 && port <= 65535 else {
            logger.error("Invalid port number provided", context: ["port": port])
            throw NetworkError.bindFailed("Invalid port number: \(port)")
        }
        
        guard let portNW = NWEndpoint.Port(rawValue: UInt16(port)) else {
            logger.error("Failed to create NWEndpoint.Port", context: ["port": port])
            throw NetworkError.bindFailed("Invalid port number: \(port)")
        }
        
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        do {
            listener = try NWListener(using: parameters, on: portNW)
            logger.debug("Created NWListener successfully")
        } catch {
            logger.error("Failed to create NWListener", context: ["error": error.localizedDescription])
            throw NetworkError.bindFailed("Failed to create listener: \(error.localizedDescription)")
        }
        
        guard let listener = listener else {
            logger.error("NWListener is nil after creation")
            throw NetworkError.bindFailed("Failed to initialize listener")
        }
        
        listener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            
            switch state {
            case .ready:
                self.isListening = true
                self.logger.info("TCP server is ready and listening")
            case .failed(let error):
                self.isListening = false
                self.logger.error("TCP server failed", context: ["error": error.localizedDescription])
            case .cancelled:
                self.isListening = false
                self.logger.info("TCP server was cancelled")
            case .waiting(let error):
                self.logger.warning("TCP server is waiting", context: ["error": error.localizedDescription])
            case .setup:
                self.logger.debug("TCP server is setting up")
            @unknown default:
                self.logger.warning("TCP server entered unknown state")
            }
        }
        
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        listener.start(queue: queue)
        logger.debug("Started NWListener on queue")
        
        // Wait a moment for the listener to start
        let semaphore = DispatchSemaphore(value: 0)
        queue.asyncAfter(deadline: .now() + 0.1) {
            semaphore.signal()
        }
        semaphore.wait()
        
        if !isListening {
            logger.error("Failed to start listening after initialization", context: ["port": port])
            throw NetworkError.bindFailed("Failed to start listening on port \(port)")
        }
        
        logger.info("TCP server started successfully", context: ["port": port])
    }
    
    /// Stop the TCP server
    public func stop() throws {
        guard isListening else {
            logger.warning("Attempted to stop TCP server that is not running")
            throw ServerError.notRunning
        }
        
        logger.info("Stopping TCP server", context: ["activeConnections": connections.count])
        
        // Close all existing connections
        for connection in connections.values {
            do {
                try connection.close()
                logger.debug("Closed connection", context: ["connectionId": connection.id.uuidString])
            } catch {
                logger.warning("Failed to close connection during shutdown", context: [
                    "connectionId": connection.id.uuidString,
                    "error": error.localizedDescription
                ])
            }
        }
        connections.removeAll()
        
        // Stop the listener
        listener?.cancel()
        listener = nil
        isListening = false
        
        logger.info("TCP server stopped successfully")
    }
    
    /// Check if the server is running
    public func isRunning() -> Bool {
        return isListening
    }
    
    /// Handle new incoming connections
    private func handleNewConnection(_ nwConnection: NWConnection) {
        let clientConnection = TCPClientConnection(connection: nwConnection)
        connections[clientConnection.id] = clientConnection
        
        logger.info("New client connection established", context: [
            "connectionId": clientConnection.id.uuidString,
            "totalConnections": connections.count
        ])
        
        // Set up disconnection handler for proper resource cleanup (requirement 2.5)
        clientConnection.onDisconnected = { [weak self] connectionId in
            guard let self = self else { return }
            
            if let connection = self.connections.removeValue(forKey: connectionId) {
                self.logger.info("Client disconnected", context: [
                    "connectionId": connectionId.uuidString,
                    "remainingConnections": self.connections.count
                ])
                self.onClientDisconnected?(connection)
            }
        }
        
        // Set up error handler for logging (requirement 2.3)
        clientConnection.onError = { [weak self] error in
            self?.logger.error("Client connection error", context: [
                "connectionId": clientConnection.id.uuidString,
                "error": error.localizedDescription
            ])
        }
        
        // Start the connection
        clientConnection.start()
        
        // Notify about new connection
        onClientConnected?(clientConnection)
    }
}