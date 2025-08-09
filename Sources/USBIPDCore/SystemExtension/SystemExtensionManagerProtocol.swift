//
//  SystemExtensionManagerProtocol.swift
//  USBIPDCore
//
//  Protocol interface for SystemExtensionManager to avoid circular dependencies
//  Provides the essential methods needed by recovery and update managers
//

import Foundation
import Common

/// Protocol defining the SystemExtensionManager interface for lifecycle operations
/// This avoids circular dependencies between USBIPDCore and SystemExtension modules
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

/// System Extension status information
/// Lightweight status structure that doesn't depend on SystemExtension module
public struct SystemExtensionStatus {
    /// Whether the System Extension is currently running
    public let isRunning: Bool
    
    /// Number of claimed devices
    public let claimedDevicesCount: Int
    
    /// Last start time
    public let lastStartTime: Date
    
    /// Error count since last restart
    public let errorCount: Int
    
    /// Memory usage in bytes
    public let memoryUsage: Int
    
    /// System Extension version
    public let version: String
    
    public init(isRunning: Bool, claimedDevicesCount: Int, lastStartTime: Date, errorCount: Int, memoryUsage: Int, version: String) {
        self.isRunning = isRunning
        self.claimedDevicesCount = claimedDevicesCount
        self.lastStartTime = lastStartTime
        self.errorCount = errorCount
        self.memoryUsage = memoryUsage
        self.version = version
    }
}