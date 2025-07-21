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
            throw NetworkError.connectionClosed
        }
        
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                // Log the error and notify error handler (requirement 2.3)
                print("TCP connection send error: \(error.localizedDescription)")
                self?.onError?(NetworkError.sendFailed(error.localizedDescription))
            }
        })
    }
    
    /// Close the connection
    public func close() throws {
        connection.cancel()
        isActive = false
    }
    
    /// Start receiving data from the connection
    private func startReceiving() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                // Log the error and attempt graceful recovery (requirement 2.3)
                print("TCP connection receive error: \(error.localizedDescription)")
                self.onError?(NetworkError.receiveFailed(error.localizedDescription))
                self.handleDisconnection()
                return
            }
            
            if let data = data, !data.isEmpty {
                self.onDataReceived?(data)
            }
            
            if isComplete {
                self.handleDisconnection()
            } else if self.isActive {
                // Continue receiving
                self.startReceiving()
            }
        }
    }
    
    /// Handle connection disconnection
    private func handleDisconnection() {
        // Clean up resources gracefully (requirement 2.5)
        isActive = false
        
        // Notify about disconnection
        onDisconnected?(id)
        
        // Clear callbacks to prevent retain cycles
        onDataReceived = nil
        onError = nil
        onDisconnected = nil
    }
}