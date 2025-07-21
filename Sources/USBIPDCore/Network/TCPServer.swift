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
    
    /// Callback for client connection events
    public var onClientConnected: ((ClientConnection) -> Void)?
    
    /// Callback for client disconnection events
    public var onClientDisconnected: ((ClientConnection) -> Void)?
    
    public init() {}
    
    /// Start the TCP server on the specified port
    public func start(port: Int) throws {
        guard !isListening else {
            throw ServerError.alreadyRunning
        }
        
        // Validate port range
        guard port > 0 && port <= 65535 else {
            throw NetworkError.bindFailed("Invalid port number: \(port)")
        }
        
        guard let portNW = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw NetworkError.bindFailed("Invalid port number: \(port)")
        }
        
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        do {
            listener = try NWListener(using: parameters, on: portNW)
        } catch {
            throw NetworkError.bindFailed("Failed to create listener: \(error.localizedDescription)")
        }
        
        guard let listener = listener else {
            throw NetworkError.bindFailed("Failed to initialize listener")
        }
        
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isListening = true
            case .failed(let error):
                self?.isListening = false
                // Log error - in a real implementation, we'd use a proper logger
                print("TCP Server failed: \(error)")
            case .cancelled:
                self?.isListening = false
            default:
                break
            }
        }
        
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        listener.start(queue: queue)
        
        // Wait a moment for the listener to start
        let semaphore = DispatchSemaphore(value: 0)
        queue.asyncAfter(deadline: .now() + 0.1) {
            semaphore.signal()
        }
        semaphore.wait()
        
        if !isListening {
            throw NetworkError.bindFailed("Failed to start listening on port \(port)")
        }
    }
    
    /// Stop the TCP server
    public func stop() throws {
        guard isListening else {
            throw ServerError.notRunning
        }
        
        // Close all existing connections
        for connection in connections.values {
            try? connection.close()
        }
        connections.removeAll()
        
        // Stop the listener
        listener?.cancel()
        listener = nil
        isListening = false
    }
    
    /// Check if the server is running
    public func isRunning() -> Bool {
        return isListening
    }
    
    /// Handle new incoming connections
    private func handleNewConnection(_ nwConnection: NWConnection) {
        let clientConnection = TCPClientConnection(connection: nwConnection)
        connections[clientConnection.id] = clientConnection
        
        // Set up disconnection handler for proper resource cleanup (requirement 2.5)
        clientConnection.onDisconnected = { [weak self] connectionId in
            if let connection = self?.connections.removeValue(forKey: connectionId) {
                print("Client disconnected: \(connectionId)")
                self?.onClientDisconnected?(connection)
            }
        }
        
        // Set up error handler for logging (requirement 2.3)
        clientConnection.onError = { error in
            print("Client connection error: \(error.localizedDescription)")
        }
        
        // Start the connection
        clientConnection.start()
        
        // Notify about new connection
        onClientConnected?(clientConnection)
    }
}