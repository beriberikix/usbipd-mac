// MockSystemExtension.swift
// Comprehensive System Extension mock for development environment testing
// Consolidates System Extension testing capabilities with enhanced reliability features

import Foundation
import SystemExtensions
import Common
@testable import USBIPDCore

// MARK: - Mock System Extension Manager

/// Comprehensive mock for System Extension operations in development environment
/// Provides reliable, predictable testing without requiring actual System Extension installation
public class MockSystemExtensionManager {
    
    // MARK: - Mock State
    
    /// Current System Extension installation state
    public var currentState: SystemExtensionState = .notInstalled
    
    /// Control whether operations should succeed or fail
    public var shouldFailInstallation = false
    public var shouldFailUninstallation = false
    public var shouldFailActivation = false
    public var shouldFailDeactivation = false
    
    /// Specific errors to return for different operations
    public var installationError: Error?
    public var uninstallationError: Error?
    public var activationError: Error?
    public var deactivationError: Error?
    
    /// Simulate installation time delays
    public var installationDelay: TimeInterval = 0.1
    public var uninstallationDelay: TimeInterval = 0.05
    
    /// Track operation calls for verification
    public private(set) var installationCalls: [Date] = []
    public private(set) var uninstallationCalls: [Date] = []
    public private(set) var activationCalls: [Date] = []
    public private(set) var deactivationCalls: [Date] = []
    public private(set) var statusCheckCalls: [Date] = []
    
    /// Bundle validation state
    public var bundleValidationResult = true
    public var bundleValidationError: Error?
    
    /// Code signing state  
    public var codeSigningValid = true
    public var codeSigningError: Error?
    
    /// System requirements check
    public var systemRequirementsMet = true
    public var systemRequirementsError: Error?
    
    // MARK: - Mock Extension Properties
    
    public let mockBundleIdentifier = "com.mock.usbipd.systemextension"
    public let mockTeamIdentifier = "MOCK123456"
    public let mockVersion = "1.0.0"
    
    // MARK: - Development Environment Features
    
    /// Enable detailed debug logging
    public var debugLoggingEnabled = true
    
    /// Simulate various system states
    public var simulatedSystemState: MockSystemState = .normal
    
    /// Track performance metrics
    public private(set) var operationTimings: [String: TimeInterval] = [:]
    
    public init() {}
    
    // MARK: - Reset and Configuration
    
    /// Reset all mock state for clean testing
    public func reset() {
        currentState = .notInstalled
        shouldFailInstallation = false
        shouldFailUninstallation = false
        shouldFailActivation = false
        shouldFailDeactivation = false
        
        installationError = nil
        uninstallationError = nil
        activationError = nil
        deactivationError = nil
        
        installationDelay = 0.1
        uninstallationDelay = 0.05
        
        installationCalls.removeAll()
        uninstallationCalls.removeAll()
        activationCalls.removeAll()
        deactivationCalls.removeAll()
        statusCheckCalls.removeAll()
        
        bundleValidationResult = true
        bundleValidationError = nil
        codeSigningValid = true
        codeSigningError = nil
        systemRequirementsMet = true
        systemRequirementsError = nil
        
        simulatedSystemState = .normal
        operationTimings.removeAll()
    }
    
    // MARK: - System Extension Operations
    
    /// Install System Extension
    public func installSystemExtension() async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        installationCalls.append(Date())
        
        if debugLoggingEnabled {
            print("MOCK: Installing System Extension...")
        }
        
        // Simulate installation delay
        if installationDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(installationDelay * 1_000_000_000))
        }
        
        // Check for configured failure
        if shouldFailInstallation {
            let error = installationError ?? SystemExtensionError.installationFailed("Mock installation failure")
            if debugLoggingEnabled {
                print("MOCK: Installation failed: \(error)")
            }
            throw error
        }
        
        // Check system requirements
        if !systemRequirementsMet {
            let error = systemRequirementsError ?? SystemExtensionError.systemRequirementsNotMet("Mock system requirements failure")
            if debugLoggingEnabled {
                print("MOCK: System requirements not met: \(error)")
            }
            throw error
        }
        
        // Check bundle validation
        if !bundleValidationResult {
            let error = bundleValidationError ?? SystemExtensionError.bundleValidationFailed("Mock bundle validation failure")
            if debugLoggingEnabled {
                print("MOCK: Bundle validation failed: \(error)")
            }
            throw error
        }
        
        // Check code signing
        if !codeSigningValid {
            let error = codeSigningError ?? SystemExtensionError.codeSigningInvalid("Mock code signing failure")
            if debugLoggingEnabled {
                print("MOCK: Code signing invalid: \(error)")
            }
            throw error
        }
        
        // Simulate state transitions
        currentState = .installing
        
        // Simulate brief processing time
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        currentState = .installed
        
        if debugLoggingEnabled {
            print("MOCK: System Extension installed successfully")
        }
        
        operationTimings["installation"] = CFAbsoluteTimeGetCurrent() - startTime
    }
    
    /// Uninstall System Extension
    public func uninstallSystemExtension() async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        uninstallationCalls.append(Date())
        
        if debugLoggingEnabled {
            print("MOCK: Uninstalling System Extension...")
        }
        
        // Simulate uninstallation delay
        if uninstallationDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(uninstallationDelay * 1_000_000_000))
        }
        
        // Check for configured failure
        if shouldFailUninstallation {
            let error = uninstallationError ?? SystemExtensionError.uninstallationFailed("Mock uninstallation failure")
            if debugLoggingEnabled {
                print("MOCK: Uninstallation failed: \(error)")
            }
            throw error
        }
        
        // Simulate state transitions
        currentState = .uninstalling
        
        // Simulate brief processing time
        try await Task.sleep(nanoseconds: 25_000_000) // 25ms
        
        currentState = .notInstalled
        
        if debugLoggingEnabled {
            print("MOCK: System Extension uninstalled successfully")
        }
        
        operationTimings["uninstallation"] = CFAbsoluteTimeGetCurrent() - startTime
    }
    
    /// Activate System Extension
    public func activateSystemExtension() async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        activationCalls.append(Date())
        
        if debugLoggingEnabled {
            print("MOCK: Activating System Extension...")
        }
        
        // Check for configured failure
        if shouldFailActivation {
            let error = activationError ?? SystemExtensionError.activationFailed("Mock activation failure")
            if debugLoggingEnabled {
                print("MOCK: Activation failed: \(error)")
            }
            throw error
        }
        
        // Must be installed first
        guard currentState == .installed || currentState == .inactive else {
            let error = SystemExtensionError.invalidState("Cannot activate: extension not installed")
            if debugLoggingEnabled {
                print("MOCK: Activation failed - invalid state: \(currentState)")
            }
            throw error
        }
        
        currentState = .activating
        
        // Simulate brief processing time
        try await Task.sleep(nanoseconds: 30_000_000) // 30ms
        
        currentState = .active
        
        if debugLoggingEnabled {
            print("MOCK: System Extension activated successfully")
        }
        
        operationTimings["activation"] = CFAbsoluteTimeGetCurrent() - startTime
    }
    
    /// Deactivate System Extension
    public func deactivateSystemExtension() async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        deactivationCalls.append(Date())
        
        if debugLoggingEnabled {
            print("MOCK: Deactivating System Extension...")
        }
        
        // Check for configured failure
        if shouldFailDeactivation {
            let error = deactivationError ?? SystemExtensionError.deactivationFailed("Mock deactivation failure")
            if debugLoggingEnabled {
                print("MOCK: Deactivation failed: \(error)")
            }
            throw error
        }
        
        // Must be active first
        guard currentState == .active else {
            let error = SystemExtensionError.invalidState("Cannot deactivate: extension not active")
            if debugLoggingEnabled {
                print("MOCK: Deactivation failed - invalid state: \(currentState)")
            }
            throw error
        }
        
        currentState = .deactivating
        
        // Simulate brief processing time
        try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        
        currentState = .inactive
        
        if debugLoggingEnabled {
            print("MOCK: System Extension deactivated successfully")
        }
        
        operationTimings["deactivation"] = CFAbsoluteTimeGetCurrent() - startTime
    }
    
    /// Get current System Extension status
    public func getSystemExtensionStatus() -> SystemExtensionStatus {
        statusCheckCalls.append(Date())
        
        if debugLoggingEnabled {
            print("MOCK: Checking System Extension status: \(currentState)")
        }
        
        return SystemExtensionStatus(
            state: currentState,
            bundleIdentifier: mockBundleIdentifier,
            teamIdentifier: mockTeamIdentifier,
            version: mockVersion,
            isCodeSigningValid: codeSigningValid,
            lastError: getLastError()
        )
    }
    
    /// Validate System Extension bundle
    public func validateBundle(at path: String) throws -> Bool {
        if debugLoggingEnabled {
            print("MOCK: Validating bundle at path: \(path)")
        }
        
        if !bundleValidationResult {
            if let error = bundleValidationError {
                throw error
            } else {
                throw SystemExtensionError.bundleValidationFailed("Mock bundle validation failure")
            }
        }
        
        return true
    }
    
    /// Check code signing validity
    public func validateCodeSigning() throws -> Bool {
        if debugLoggingEnabled {
            print("MOCK: Validating code signing")
        }
        
        if !codeSigningValid {
            if let error = codeSigningError {
                throw error
            } else {
                throw SystemExtensionError.codeSigningInvalid("Mock code signing failure")
            }
        }
        
        return true
    }
    
    /// Check system requirements
    public func checkSystemRequirements() throws -> Bool {
        if debugLoggingEnabled {
            print("MOCK: Checking system requirements")
        }
        
        // Simulate system state checks
        switch simulatedSystemState {
        case .normal:
            break
        case .sipEnabled:
            if debugLoggingEnabled {
                print("MOCK: SIP is enabled, may affect installation")
            }
        case .insufficientPermissions:
            throw SystemExtensionError.systemRequirementsNotMet("Insufficient permissions")
        case .incompatibleOSVersion:
            throw SystemExtensionError.systemRequirementsNotMet("Incompatible OS version")
        }
        
        if !systemRequirementsMet {
            if let error = systemRequirementsError {
                throw error
            } else {
                throw SystemExtensionError.systemRequirementsNotMet("Mock system requirements failure")
            }
        }
        
        return true
    }
    
    // MARK: - Test Scenario Configuration
    
    /// Configure mock for successful installation scenario
    public func setupSuccessfulInstallationScenario() {
        reset()
        shouldFailInstallation = false
        bundleValidationResult = true
        codeSigningValid = true
        systemRequirementsMet = true
        simulatedSystemState = .normal
    }
    
    /// Configure mock for failed installation scenario
    public func setupFailedInstallationScenario(error: Error? = nil) {
        reset()
        shouldFailInstallation = true
        installationError = error ?? SystemExtensionError.installationFailed("Mock installation failure")
    }
    
    /// Configure mock for permission denied scenario
    public func setupPermissionDeniedScenario() {
        reset()
        simulatedSystemState = .insufficientPermissions
        systemRequirementsMet = false
        systemRequirementsError = SystemExtensionError.systemRequirementsNotMet("Insufficient permissions")
    }
    
    /// Configure mock for code signing failure scenario
    public func setupCodeSigningFailureScenario() {
        reset()
        codeSigningValid = false
        codeSigningError = SystemExtensionError.codeSigningInvalid("Code signing validation failed")
    }
    
    /// Configure mock for bundle validation failure scenario
    public func setupBundleValidationFailureScenario() {
        reset()
        bundleValidationResult = false
        bundleValidationError = SystemExtensionError.bundleValidationFailed("Bundle validation failed")
    }
    
    // MARK: - Development Statistics
    
    /// Get comprehensive statistics for test verification
    public func getDevelopmentStatistics() -> SystemExtensionMockStatistics {
        return SystemExtensionMockStatistics(
            totalOperationCalls: installationCalls.count + uninstallationCalls.count + activationCalls.count + deactivationCalls.count,
            installationAttempts: installationCalls.count,
            uninstallationAttempts: uninstallationCalls.count,
            activationAttempts: activationCalls.count,
            deactivationAttempts: deactivationCalls.count,
            statusChecks: statusCheckCalls.count,
            currentState: currentState,
            operationTimings: operationTimings
        )
    }
    
    // MARK: - Private Helper Methods
    
    private func getLastError() -> Error? {
        // Return the most recent error based on current state
        switch currentState {
        case .installationFailed:
            return installationError
        case .uninstallationFailed:
            return uninstallationError
        case .activationFailed:
            return activationError
        case .deactivationFailed:
            return deactivationError
        default:
            return nil
        }
    }
}

// MARK: - Supporting Types

/// System Extension states for testing
public enum SystemExtensionState: String, CaseIterable {
    case notInstalled = "not_installed"
    case installing = "installing"
    case installed = "installed"
    case installationFailed = "installation_failed"
    case uninstalling = "uninstalling"
    case uninstallationFailed = "uninstallation_failed"
    case activating = "activating"
    case active = "active"
    case activationFailed = "activation_failed"
    case deactivating = "deactivating"
    case inactive = "inactive"
    case deactivationFailed = "deactivation_failed"
}

/// System Extension status information
public struct SystemExtensionStatus {
    public let state: SystemExtensionState
    public let bundleIdentifier: String
    public let teamIdentifier: String
    public let version: String
    public let isCodeSigningValid: Bool
    public let lastError: Error?
    
    public init(
        state: SystemExtensionState,
        bundleIdentifier: String,
        teamIdentifier: String,
        version: String,
        isCodeSigningValid: Bool,
        lastError: Error?
    ) {
        self.state = state
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.version = version
        self.isCodeSigningValid = isCodeSigningValid
        self.lastError = lastError
    }
}

/// Mock system states for testing different scenarios
public enum MockSystemState {
    case normal
    case sipEnabled
    case insufficientPermissions
    case incompatibleOSVersion
}

/// System Extension errors for testing
public enum SystemExtensionError: Error, LocalizedError {
    case installationFailed(String)
    case uninstallationFailed(String)
    case activationFailed(String)
    case deactivationFailed(String)
    case bundleValidationFailed(String)
    case codeSigningInvalid(String)
    case systemRequirementsNotMet(String)
    case invalidState(String)
    
    public var errorDescription: String? {
        switch self {
        case .installationFailed(let message):
            return "Installation failed: \(message)"
        case .uninstallationFailed(let message):
            return "Uninstallation failed: \(message)"
        case .activationFailed(let message):
            return "Activation failed: \(message)"
        case .deactivationFailed(let message):
            return "Deactivation failed: \(message)"
        case .bundleValidationFailed(let message):
            return "Bundle validation failed: \(message)"
        case .codeSigningInvalid(let message):
            return "Code signing invalid: \(message)"
        case .systemRequirementsNotMet(let message):
            return "System requirements not met: \(message)"
        case .invalidState(let message):
            return "Invalid state: \(message)"
        }
    }
}

/// Statistics for System Extension mock operations
public struct SystemExtensionMockStatistics {
    public let totalOperationCalls: Int
    public let installationAttempts: Int
    public let uninstallationAttempts: Int
    public let activationAttempts: Int
    public let deactivationAttempts: Int
    public let statusChecks: Int
    public let currentState: SystemExtensionState
    public let operationTimings: [String: TimeInterval]
    
    public init(
        totalOperationCalls: Int,
        installationAttempts: Int,
        uninstallationAttempts: Int,
        activationAttempts: Int,
        deactivationAttempts: Int,
        statusChecks: Int,
        currentState: SystemExtensionState,
        operationTimings: [String: TimeInterval]
    ) {
        self.totalOperationCalls = totalOperationCalls
        self.installationAttempts = installationAttempts
        self.uninstallationAttempts = uninstallationAttempts
        self.activationAttempts = activationAttempts
        self.deactivationAttempts = deactivationAttempts
        self.statusChecks = statusChecks
        self.currentState = currentState
        self.operationTimings = operationTimings
    }
}

// MARK: - Mock Device Claiming Method

/// Device claiming methods for System Extension testing
public enum DeviceClaimMethod {
    case exclusiveAccess
    case driverUnbinding
    case ioUserClient
}