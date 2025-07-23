// NetworkService.swift
// Network service implementation for USB/IP server

import Foundation

/// Protocol for network service
public protocol NetworkService {
    /// Start the network service on the specified port
    func start(port: Int) throws
    
    /// Stop the network service
    func stop() throws
    
    /// Check if the network service is running
    func isRunning() -> Bool
    
    /// Callback for client connection events
    var onClientConnected: ((ClientConnection) -> Void)? { get set }
    
    /// Callback for client disconnection events
    var onClientDisconnected: ((ClientConnection) -> Void)? { get set }
}

/// Protocol for client connections
public protocol ClientConnection {
    /// Unique identifier for the connection
    var id: UUID { get }
    
    /// Send data to the client
    func send(data: Data) throws
    
    /// Close the connection
    func close() throws
    
    /// Callback for data received events
    var onDataReceived: ((Data) -> Void)? { get set }
    
    /// Callback for error events
    var onError: ((Error) -> Void)? { get set }
}