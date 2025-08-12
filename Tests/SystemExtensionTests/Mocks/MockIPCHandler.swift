// MockIPCHandler.swift
// Mock implementation of IPCHandler for testing System Extension IPC logic

import Foundation
import Common
@testable import SystemExtension
@testable import USBIPDCore

// MARK: - Mock IPC Handler

/// Mock implementation of IPCHandler protocol for testing IPC communication
/// without requiring actual XPC connections
public class MockIPCHandler: USBIPDCore.IPCHandler {
    
    // MARK: - Mock Configuration
    
    /// Whether operations should succeed
    public var shouldSucceed = true
    
    /// Error to throw when operations fail
    public var startError: Error?
    
    // MARK: - Mock State
    
    /// Whether the listener is currently active
    public var isListeningValue = false
    
    /// Track method calls for verification
    public var startListenerCalled = false
    public var stopListenerCalled = false
    public var sendResponseCalled = false
    public var authenticateClientCalled = false
    
    /// Track authentication calls
    public var authenticatedClients: Set<String> = []
    public var authenticationResults: [String: Bool] = [:]
    
    /// Track sent responses
    public var sentResponses: [IPCResponse] = []
    
    /// Mock statistics
    private var mockStatistics = USBIPDCore.IPCStatistics()
    
    /// Simulate network delay
    public var simulatedDelay: TimeInterval = 0.0
    
    // MARK: - IPCHandler Protocol Implementation
    
    public func startListener() throws {
        startListenerCalled = true
        
        if !shouldSucceed, let error = startError {
            throw error
        }
        
        isListeningValue = true
        // Note: USBIPDCore.IPCStatistics doesn't have startTime field
    }
    
    public func stopListener() {
        stopListenerCalled = true
        isListeningValue = false
        // Note: USBIPDCore.IPCStatistics doesn't have stopTime field
    }
    
    public func sendResponse(to request: IPCRequest, response: IPCResponse) throws {
        sendResponseCalled = true
        
        if !shouldSucceed {
            throw SystemExtensionError.ipcError("Mock send response failure")
        }
        
        // Simulate network delay
        if simulatedDelay > 0 {
            Thread.sleep(forTimeInterval: simulatedDelay)
        }
        
        sentResponses.append(response)
        // Note: USBIPDCore.IPCStatistics doesn't have recordResponse method
    }
    
    public func authenticateClient(clientID: String) -> Bool {
        authenticateClientCalled = true
        
        // Check if we have a configured result for this client
        if let result = authenticationResults[clientID] {
            if result {
                authenticatedClients.insert(clientID)
                // Note: USBIPDCore.IPCStatistics doesn't have authenticatedClients field
            } else {
                // Note: USBIPDCore.IPCStatistics doesn't have authenticationFailures field
            }
            return result
        }
        
        // Default behavior - allow all clients for testing
        if shouldSucceed {
            authenticatedClients.insert(clientID)
            // Note: USBIPDCore.IPCStatistics doesn't have authenticatedClients field
            return true
        } else {
            // Note: USBIPDCore.IPCStatistics doesn't have authenticationFailures field
            return false
        }
    }
    
    public func isListening() -> Bool {
        return isListeningValue
    }
    
    public func getStatistics() -> USBIPDCore.IPCStatistics {
        return mockStatistics
    }
    
    // MARK: - Mock Helper Methods
    
    /// Reset all call flags and state
    public func resetCallFlags() {
        startListenerCalled = false
        stopListenerCalled = false
        sendResponseCalled = false
        authenticateClientCalled = false
    }
    
    /// Reset all mock state
    public func reset() {
        resetCallFlags()
        isListeningValue = false
        authenticatedClients.removeAll()
        authenticationResults.removeAll()
        sentResponses.removeAll()
        mockStatistics = USBIPDCore.IPCStatistics()
        shouldSucceed = true
        startError = nil
        simulatedDelay = 0.0
    }
    
    /// Configure client authentication result
    public func setAuthenticationResult(for clientID: String, success: Bool) {
        authenticationResults[clientID] = success
    }
    
    /// Simulate receiving a request (for testing request handling)
    public func simulateRequest(_ request: IPCRequest) {
        // Note: USBIPDCore.IPCStatistics doesn't have recordRequest method
    }
    
    /// Get the last sent response
    public var lastSentResponse: IPCResponse? {
        return sentResponses.last
    }
    
    /// Get count of responses sent
    public var responseCount: Int {
        return sentResponses.count
    }
    
    /// Check if a specific client was authenticated
    public func wasClientAuthenticated(_ clientID: String) -> Bool {
        return authenticatedClients.contains(clientID)
    }
}