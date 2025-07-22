// USBIPServer.swift
// Core server protocol for USB/IP server

import Foundation

/// Protocol for USB/IP server implementation
public protocol USBIPServer {
    /// Start the USB/IP server
    func start() throws
    
    /// Stop the USB/IP server
    func stop() throws
    
    /// Check if the server is running
    func isRunning() -> Bool
    
    /// Callback for error events
    var onError: ((Error) -> Void)? { get set }
}