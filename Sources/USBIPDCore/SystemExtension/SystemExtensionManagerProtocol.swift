// SystemExtensionManagerProtocol.swift
// Protocol interface for SystemExtensionManager to avoid circular dependencies

import Foundation
import Common

/// Protocol defining the SystemExtensionManager interface for lifecycle operations
public protocol SystemExtensionManagerProtocol: AnyObject {
    /// Start the System Extension
    /// - Throws: Error if startup fails
    func start() throws
    
    /// Stop the System Extension
    /// - Throws: Error if shutdown fails
    func stop() throws
    
    /// Get current System Extension status
    /// - Returns: Status information including running state
    func getStatus() -> SystemExtensionStatus
    
    /// Perform health check on the System Extension
    /// - Returns: True if healthy, false if issues detected
    func performHealthCheck() -> Bool
}

/// Make SystemExtensionManager conform to the protocol
extension SystemExtensionManager: SystemExtensionManagerProtocol {}