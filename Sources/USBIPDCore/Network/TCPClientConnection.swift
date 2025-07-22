// TCPClientConnection.swift
// TCP client connection implementation using Network.framework

import Foundation
import Network
import Common

/// TCP client connection implementation
public class TCPClientConnection: ClientConnection {
    /// Unique identifier for the connection
    public let id = UUID()
    
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "TCPClientConnection", qos: .userInitiated)
    private var isActive = false
    private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "connection")
    
    /// Callback for data received events
    public var onDataReceived: ((Data) -> Void)?
    
    /// Callback for error events
    public var onError: ((Error) -> Void)?
    
    /// Internal callback for disconnection events
    internal var onDisconnected: ((UUID) -> Void)?
    
    /// Initialize with an NWConnection
    internal init(connection: NWConnection) {
        self.connection = connection
        setupConnection()
    }
    
    /// Set up the connection handlers
    private func setupConnection() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            
            switch state {
            case .ready:
                self.isActive = true
                self.startReceiving()
            case .failed(let error):
                self.isActive = false
                self.onError?(NetworkError.connectionFailed(error.localizedDescription))
                self.handleDisconnection()
            case .cancelled:
                self.isActive = false
                self.handleDisconnection()
            default:
                break
            }
        }
    }
    
    /// Start the connection
    internal func start() {
        connection.start(queue: queue)
    }
    
    /// Send data to the client
    public func send(data: Data) throws {
        guard isActive else {
            logger.error("Attempted to send data on inactive connection", context: ["connectionId": id.uuidString])
            throw NetworkError.connectionClosed
        }
        
        logger.debug("Sending data to client", context: [
            "connectionId": id.uuidString,
            "dataSize": data.count
        ])
        
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("TCP connection send error", context: [
                    "connectionId": self.id.uuidString,
                    "error": error.localizedDescription
                ])
                self.onError?(NetworkError.sendFailed(error.localizedDescription))
            } else {
                self.logger.debug("Data sent successfully", context: [
                    "connectionId": self.id.uuidString,
                    "dataSize": data.count
                ])
            }
        })
    }
    
    /// Close the connection
    public func close() throws {
        logger.info("Closing client connection", context: ["connectionId": id.uuidString])
        connection.cancel()
        isActive = false
        logger.debug("Client connection closed", context: ["connectionId": id.uuidString])
    }
    
    /// Start receiving data from the connection
    private func startReceiving() {
        logger.debug("Starting to receive data", context: ["connectionId": id.uuidString])
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("TCP connection receive error", context: [
                    "connectionId": self.id.uuidString,
                    "error": error.localizedDescription
                ])
                self.onError?(NetworkError.receiveFailed(error.localizedDescription))
                self.handleDisconnection()
                return
            }
            
            if let data = data, !data.isEmpty {
                self.logger.debug("Received data from client", context: [
                    "connectionId": self.id.uuidString,
                    "dataSize": data.count
                ])
                self.onDataReceived?(data)
            }
            
            if isComplete {
                self.logger.info("Connection marked as complete", context: ["connectionId": self.id.uuidString])
                self.handleDisconnection()
            } else if self.isActive {
                // Continue receiving
                self.startReceiving()
            }
        }
    }
    
    /// Handle connection disconnection
    private func handleDisconnection() {
        logger.info("Handling client disconnection", context: ["connectionId": id.uuidString])
        
        // Clean up resources gracefully (requirement 2.5)
        isActive = false
        
        // Notify about disconnection
        onDisconnected?(id)
        
        // Clear callbacks to prevent retain cycles
        onDataReceived = nil
        onError = nil
        onDisconnected = nil
        
        logger.debug("Client disconnection handled, resources cleaned up", context: ["connectionId": id.uuidString])
    }
}