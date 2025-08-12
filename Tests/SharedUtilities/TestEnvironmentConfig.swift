// TestEnvironmentConfig.swift
// Test environment configuration and suite protocols for environment-aware test execution
// This implements the TestEnvironmentConfig struct and TestSuite protocol from the design

import Foundation
import XCTest
@testable import USBIPDCore
@testable import USBIPDCLI
@testable import Common

// MARK: - Test Environment Types

/// Available test execution environments
public enum TestEnvironment: String, CaseIterable {
    case development
    case ci
    case production
    
    /// Human-readable name for the environment
    public var displayName: String {
        switch self {
        case .development:
            return "Development"
        case .ci:
            return "CI/Automated"
        case .production:
            return "Production/Release"
        }
    }
    
    /// Expected execution time limits for each environment
    public var executionTimeLimit: TimeInterval {
        switch self {
        case .development:
            return 60.0 // 1 minute
        case .ci:
            return 180.0 // 3 minutes
        case .production:
            return 600.0 // 10 minutes
        }
    }
}

// MARK: - Test Environment Capabilities

/// Test environment capability flags
public struct TestEnvironmentCapabilities: OptionSet {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    /// Can access real hardware devices
    public static let hardwareAccess = TestEnvironmentCapabilities(rawValue: 1 << 0)
    
    /// Can install System Extensions
    public static let systemExtensionInstall = TestEnvironmentCapabilities(rawValue: 1 << 1)
    
    /// Can run QEMU integration tests
    public static let qemuIntegration = TestEnvironmentCapabilities(rawValue: 1 << 2)
    
    /// Can perform network operations
    public static let networkAccess = TestEnvironmentCapabilities(rawValue: 1 << 3)
    
    /// Can write to filesystem
    public static let filesystemWrite = TestEnvironmentCapabilities(rawValue: 1 << 4)
    
    /// Can run privileged operations
    public static let privilegedOperations = TestEnvironmentCapabilities(rawValue: 1 << 5)
    
    /// Can run time-intensive operations
    public static let timeIntensiveOperations = TestEnvironmentCapabilities(rawValue: 1 << 6)
    
    /// All capabilities available
    public static let all: TestEnvironmentCapabilities = [
        .hardwareAccess,
        .systemExtensionInstall,
        .qemuIntegration,
        .networkAccess,
        .filesystemWrite,
        .privilegedOperations,
        .timeIntensiveOperations
    ]
}

// MARK: - Test Environment Configuration

/// Configuration for test environment execution and validation
public struct TestEnvironmentConfig {
    
    /// Current test environment
    public let environment: TestEnvironment
    
    /// Available capabilities in this environment
    public let capabilities: TestEnvironmentCapabilities
    
    /// Maximum execution time for test suites
    public let maxExecutionTime: TimeInterval
    
    /// Whether to use mocks for unavailable resources
    public let useMocksForUnavailableResources: Bool
    
    /// Whether to skip tests that require unavailable capabilities
    public let skipTestsRequiringUnavailableCapabilities: Bool
    
    /// Whether to run tests in parallel
    public let enableParallelExecution: Bool
    
    /// Custom timeout overrides for specific test categories
    public let timeoutOverrides: [String: TimeInterval]
    
    /// Environment-specific configuration data
    public let environmentData: [String: Any]
    
    // MARK: - Initialization
    
    public init(
        environment: TestEnvironment,
        capabilities: TestEnvironmentCapabilities = [],
        maxExecutionTime: TimeInterval? = nil,
        useMocksForUnavailableResources: Bool = true,
        skipTestsRequiringUnavailableCapabilities: Bool = false,
        enableParallelExecution: Bool = true,
        timeoutOverrides: [String: TimeInterval] = [:],
        environmentData: [String: Any] = [:]
    ) {
        self.environment = environment
        self.capabilities = capabilities
        self.maxExecutionTime = maxExecutionTime ?? environment.executionTimeLimit
        self.useMocksForUnavailableResources = useMocksForUnavailableResources
        self.skipTestsRequiringUnavailableCapabilities = skipTestsRequiringUnavailableCapabilities
        self.enableParallelExecution = enableParallelExecution
        self.timeoutOverrides = timeoutOverrides
        self.environmentData = environmentData
    }
    
    // MARK: - Capability Checking
    
    /// Check if a specific capability is available
    public func hasCapability(_ capability: TestEnvironmentCapabilities) -> Bool {
        return capabilities.contains(capability)
    }
    
    /// Check if all required capabilities are available
    public func hasCapabilities(_ requiredCapabilities: TestEnvironmentCapabilities) -> Bool {
        return capabilities.contains(requiredCapabilities)
    }
    
    /// Get timeout for a specific test category
    public func timeout(for category: String) -> TimeInterval {
        return timeoutOverrides[category] ?? maxExecutionTime
    }
    
    /// Check if a test should be skipped due to missing capabilities
    public func shouldSkipTest(requiringCapabilities: TestEnvironmentCapabilities) -> Bool {
        if hasCapabilities(requiringCapabilities) {
            return false
        }
        return skipTestsRequiringUnavailableCapabilities
    }
}

// MARK: - Predefined Environment Configurations

extension TestEnvironmentConfig {
    
    /// Development environment configuration - fast unit tests with comprehensive mocking
    public static let development = TestEnvironmentConfig(
        environment: .development,
        capabilities: [.networkAccess, .filesystemWrite],
        useMocksForUnavailableResources: true,
        skipTestsRequiringUnavailableCapabilities: true,
        enableParallelExecution: true,
        timeoutOverrides: [
            "unit": 5.0,
            "integration": 15.0
        ],
        environmentData: [
            "mockLevel": "comprehensive",
            "fastMode": true
        ]
    )
    
    /// CI environment configuration - reliable automated testing without hardware dependencies
    public static let ci = TestEnvironmentConfig(
        environment: .ci,
        capabilities: [.networkAccess, .filesystemWrite],
        useMocksForUnavailableResources: true,
        skipTestsRequiringUnavailableCapabilities: true,
        enableParallelExecution: true,
        timeoutOverrides: [
            "unit": 10.0,
            "integration": 30.0,
            "protocol": 20.0
        ],
        environmentData: [
            "mockLevel": "selective",
            "ciMode": true,
            "retryCount": 1
        ]
    )
    
    /// Production environment configuration - comprehensive validation including hardware
    public static let production = TestEnvironmentConfig(
        environment: .production,
        capabilities: .all,
        useMocksForUnavailableResources: false,
        skipTestsRequiringUnavailableCapabilities: false,
        enableParallelExecution: false, // Sequential for stability
        timeoutOverrides: [
            "unit": 30.0,
            "integration": 120.0,
            "qemu": 300.0,
            "systemExtension": 180.0
        ],
        environmentData: [
            "mockLevel": "minimal",
            "hardwareValidation": true,
            "comprehensiveMode": true
        ]
    )
}

// MARK: - Test Suite Protocol

/// Protocol for environment-aware test suites
public protocol TestSuite: AnyObject {
    
    /// Test environment configuration for this suite
    var environmentConfig: TestEnvironmentConfig { get }
    
    /// Required capabilities for this test suite
    var requiredCapabilities: TestEnvironmentCapabilities { get }
    
    /// Test suite category for timeout configuration
    var testCategory: String { get }
    
    /// Setup method called before suite execution
    func setUpTestSuite()
    
    /// Teardown method called after suite execution
    func tearDownTestSuite()
    
    /// Check if this test suite should run in the current environment
    func shouldRunInCurrentEnvironment() -> Bool
    
    /// Validate environment before running tests
    func validateEnvironment() throws
}

// MARK: - Default Test Suite Implementation

extension TestSuite {
    
    /// Default implementation - should run if capabilities are available or can be mocked
    public func shouldRunInCurrentEnvironment() -> Bool {
        // If we have all required capabilities, we can run
        if environmentConfig.hasCapabilities(requiredCapabilities) {
            return true
        }
        
        // If we should skip tests requiring unavailable capabilities, don't run
        if environmentConfig.shouldSkipTest(requiringCapabilities: requiredCapabilities) {
            return false
        }
        
        // If we can use mocks for unavailable resources, we can run
        return environmentConfig.useMocksForUnavailableResources
    }
    
    /// Default environment validation - check basic requirements
    public func validateEnvironment() throws {
        // Check if required capabilities are available
        let missingCapabilities = TestEnvironmentCapabilities(
            rawValue: requiredCapabilities.rawValue & ~environmentConfig.capabilities.rawValue
        )
        
        if missingCapabilities.rawValue != 0 && !environmentConfig.useMocksForUnavailableResources {
            throw TestEnvironmentError.missingCapabilities(missingCapabilities)
        }
        
        // Validate execution time limits
        let timeout = environmentConfig.timeout(for: testCategory)
        if timeout <= 0 {
            throw TestEnvironmentError.invalidConfiguration("Invalid timeout configuration")
        }
    }
    
    /// Default setup - can be overridden by implementations
    public func setUpTestSuite() {
        // Default implementation does nothing
    }
    
    /// Default teardown - can be overridden by implementations
    public func tearDownTestSuite() {
        // Default implementation does nothing
    }
}

// MARK: - Test Environment Errors

/// Errors related to test environment configuration and validation
public enum TestEnvironmentError: Error, Equatable {
    case missingCapabilities(TestEnvironmentCapabilities)
    case invalidConfiguration(String)
    case environmentNotSupported(TestEnvironment)
    case capabilityDetectionFailed(String)
    
    public var localizedDescription: String {
        switch self {
        case .missingCapabilities(let capabilities):
            return "Missing required capabilities: \(capabilities)"
        case .invalidConfiguration(let message):
            return "Invalid test environment configuration: \(message)"
        case .environmentNotSupported(let environment):
            return "Test environment not supported: \(environment.displayName)"
        case .capabilityDetectionFailed(let message):
            return "Failed to detect environment capabilities: \(message)"
        }
    }
}

// MARK: - Environment Detection

/// Utilities for detecting current test environment and capabilities
public struct TestEnvironmentDetector {
    
    /// Detect current test environment based on system properties
    public static func detectCurrentEnvironment() -> TestEnvironment {
        // Check for CI environment variables
        if ProcessInfo.processInfo.environment["CI"] != nil ||
           ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil {
            return .ci
        }
        
        // Check for production indicators (could be system capabilities, etc.)
        if canAccessHardware() && canInstallSystemExtensions() {
            return .production
        }
        
        // Default to development
        return .development
    }
    
    /// Detect available capabilities in current environment
    public static func detectAvailableCapabilities() -> TestEnvironmentCapabilities {
        var capabilities: TestEnvironmentCapabilities = []
        
        // Check for hardware access
        if canAccessHardware() {
            capabilities.insert(.hardwareAccess)
        }
        
        // Check for System Extension installation capability
        if canInstallSystemExtensions() {
            capabilities.insert(.systemExtensionInstall)
        }
        
        // Check for QEMU availability
        if canRunQEMU() {
            capabilities.insert(.qemuIntegration)
        }
        
        // Network access (assume available unless restricted)
        capabilities.insert(.networkAccess)
        
        // Filesystem write access (test by creating temp file)
        if canWriteToFilesystem() {
            capabilities.insert(.filesystemWrite)
        }
        
        // Privileged operations (check if running as admin/root)
        if canRunPrivilegedOperations() {
            capabilities.insert(.privilegedOperations)
        }
        
        // Time-intensive operations (always allowed in detection)
        capabilities.insert(.timeIntensiveOperations)
        
        return capabilities
    }
    
    /// Create environment configuration based on detection
    public static func createConfigurationForCurrentEnvironment() -> TestEnvironmentConfig {
        let environment = detectCurrentEnvironment()
        let capabilities = detectAvailableCapabilities()
        
        switch environment {
        case .development:
            return TestEnvironmentConfig(
                environment: environment,
                capabilities: capabilities
            )
        case .ci:
            return TestEnvironmentConfig.ci
        case .production:
            return TestEnvironmentConfig(
                environment: environment,
                capabilities: capabilities
            )
        }
    }
    
    // MARK: - Capability Detection Helpers
    
    private static func canAccessHardware() -> Bool {
        // Simple check - if we're not in a CI environment, assume hardware access
        return ProcessInfo.processInfo.environment["CI"] == nil
    }
    
    private static func canInstallSystemExtensions() -> Bool {
        // Check if running on macOS with admin privileges
        #if os(macOS)
        return getuid() == 0 || ProcessInfo.processInfo.environment["TEST_ALLOW_SYSEXT"] != nil
        #else
        return false
        #endif
    }
    
    private static func canRunQEMU() -> Bool {
        // Check if QEMU is available in PATH
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = ["qemu-system-x86_64"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    private static func canWriteToFilesystem() -> Bool {
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("test-write-\(UUID().uuidString)")
        
        do {
            try "test".write(to: tempFile, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: tempFile)
            return true
        } catch {
            return false
        }
    }
    
    private static func canRunPrivilegedOperations() -> Bool {
        // Check for admin/root privileges
        return getuid() == 0 || ProcessInfo.processInfo.environment["TEST_ALLOW_PRIVILEGED"] != nil
    }
}