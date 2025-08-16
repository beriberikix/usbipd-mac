// QEMUVMManagerTests.swift
// Unit tests for QEMU VM management functionality with comprehensive mocking and error scenarios
// Integrates with the Swift test framework and environment-aware testing infrastructure

import XCTest
import Foundation
@testable import Common
@testable import USBIPDCore
@testable import QEMUTestServer

// Import shared test utilities
#if canImport(SharedUtilities)
import SharedUtilities
#endif

/// Test suite for QEMU VM management functionality
final class QEMUVMManagerTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol Implementation
    
    var environmentConfig: TestEnvironmentConfig {
        return TestEnvironmentConfig.ci // CI environment for integration tests
    }
    
    var requiredCapabilities: TestEnvironmentCapabilities {
        return [.qemuIntegration, .mockingSupport]
    }
    
    // MARK: - Test Configuration
    
    /// Check if QEMU is available for testing
    private var hasQEMUCapability: Bool {
        // Check if running in CI or if QEMU is available
        return ProcessInfo.processInfo.environment["CI"] != nil || 
               ProcessInfo.processInfo.environment["QEMU_AVAILABLE"] != nil ||
               isQEMUInstalled()
    }
    
    /// Detect if QEMU is installed on the system
    private func isQEMUInstalled() -> Bool {
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
    
    // MARK: - Test Infrastructure
    
    private var logger: Logger!
    private var testConfiguration: QEMUTestConfiguration!
    private var vmManager: MockQEMUVMManager!
    private var tempDirectory: URL!
    private var originalWorkingDirectory: String!
    
    // MARK: - Test Lifecycle
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Skip tests if QEMU not available and not in CI
        if !hasQEMUCapability {
            throw XCTSkip("QEMU integration tests require QEMU installation or CI environment")
        }
        
        // Create logger for testing
        logger = Logger(
            config: LoggerConfig(level: .debug, includeTimestamp: false),
            subsystem: "com.usbipd.qemu.tests",
            category: "vm-manager"
        )
        
        // Create test configuration - use development environment for most tests
        testConfiguration = QEMUTestConfiguration(
            logger: logger,
            environment: .development
        )
        
        // Create mock VM manager
        vmManager = MockQEMUVMManager(logger: logger, configuration: testConfiguration)
        
        // Set up temporary directory for test artifacts
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("qemu-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Store original working directory
        originalWorkingDirectory = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(tempDirectory.path)
    }
    
    override func tearDownWithError() throws {
        // Restore working directory
        if let originalDir = originalWorkingDirectory {
            FileManager.default.changeCurrentDirectoryPath(originalDir)
        }
        
        // Clean up temporary directory
        if let tempDir = tempDirectory, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Clean up test resources
        vmManager = nil
        testConfiguration = nil
        logger = nil
        
        try super.tearDownWithError()
    }
    
    // MARK: - Configuration Tests
    
    func testQEMUTestConfigurationInitialization() throws {
        XCTAssertNotNil(testConfiguration)
        XCTAssertEqual(testConfiguration.getCurrentEnvironment(), environmentConfig.environment)
        
        // Test configuration validation
        XCTAssertNoThrow(try testConfiguration.validateConfiguration())
        
        // Test timeout retrieval
        let timeouts = testConfiguration.getTimeouts()
        XCTAssertGreaterThan(timeouts.readiness, 0)
        XCTAssertGreaterThan(timeouts.connection, 0)
        XCTAssertGreaterThan(timeouts.command, 0)
        XCTAssertGreaterThan(timeouts.boot, 0)
        XCTAssertGreaterThan(timeouts.shutdown, 0)
    }
    
    func testEnvironmentSpecificConfiguration() throws {
        let developmentConfig = QEMUTestConfiguration(
            logger: logger,
            environment: .development
        )
        
        let productionConfig = QEMUTestConfiguration(
            logger: logger,
            environment: .production
        )
        
        // Verify different configurations for different environments
        let devConfig = try developmentConfig.loadConfiguration()
        let prodConfig = try productionConfig.loadConfiguration()
        
        // Development should use fewer resources
        XCTAssertEqual(devConfig.vm.cpuCores, 1)
        XCTAssertEqual(devConfig.vm.memory, "128M")
        XCTAssertEqual(devConfig.testing.maxTestDuration, 60)
        
        // Production should use more resources
        XCTAssertEqual(prodConfig.vm.cpuCores, 4)
        XCTAssertEqual(prodConfig.vm.memory, "512M")
        XCTAssertEqual(prodConfig.testing.maxTestDuration, 600)
    }
    
    func testConfigurationValidationFailure() throws {
        // Test with invalid configuration
        let invalidConfigPath = tempDirectory.appendingPathComponent("invalid-config.json").path
        try "{ invalid json }".write(toFile: invalidConfigPath, atomically: true, encoding: .utf8)
        
        let invalidConfig = QEMUTestConfiguration(
            logger: logger,
            configPath: invalidConfigPath,
            environment: .development
        )
        
        // Should fall back to default configuration without throwing
        XCTAssertNoThrow(try invalidConfig.loadConfiguration())
        
        // But validation should still pass for the default config
        XCTAssertNoThrow(try invalidConfig.validateConfiguration())
    }
    
    // MARK: - VM Manager Mock Tests
    
    func testVMCreation() throws {
        let vmName = "test-vm-\(UUID().uuidString)"
        
        // Test VM creation
        let result = try vmManager.createVM(name: vmName)
        XCTAssertTrue(result.success, "VM creation should succeed")
        XCTAssertEqual(result.vmName, vmName)
        XCTAssertNotNil(result.imagePath)
        XCTAssertNotNil(result.configPath)
        
        // Verify VM was added to manager's tracking
        let vmExists = try vmManager.vmExists(name: vmName)
        XCTAssertTrue(vmExists, "VM should exist after creation")
    }
    
    func testVMCreationWithDuplicateName() throws {
        let vmName = "duplicate-vm-\(UUID().uuidString)"
        
        // Create first VM
        let result1 = try vmManager.createVM(name: vmName)
        XCTAssertTrue(result1.success)
        
        // Attempt to create VM with same name should fail
        XCTAssertThrowsError(try vmManager.createVM(name: vmName)) { error in
            XCTAssertTrue(error is QEMUVMManagerError)
            if let vmError = error as? QEMUVMManagerError {
                switch vmError {
                case .vmAlreadyExists(let existingName):
                    XCTAssertEqual(existingName, vmName)
                default:
                    XCTFail("Expected vmAlreadyExists error, got \(vmError)")
                }
            }
        }
    }
    
    func testVMStartup() throws {
        let vmName = "startup-vm-\(UUID().uuidString)"
        
        // Create VM first
        let createResult = try vmManager.createVM(name: vmName)
        XCTAssertTrue(createResult.success)
        
        // Start VM
        let startResult = try vmManager.startVM(name: vmName)
        XCTAssertTrue(startResult.success, "VM startup should succeed")
        XCTAssertEqual(startResult.vmName, vmName)
        XCTAssertNotNil(startResult.processId)
        XCTAssertNotNil(startResult.managementPort)
        
        // Verify VM is running
        let status = try vmManager.getVMStatus(name: vmName)
        XCTAssertEqual(status.state, .running)
        XCTAssertEqual(status.vmName, vmName)
        XCTAssertNotNil(status.processId)
        XCTAssertNotNil(status.uptime)
    }
    
    func testVMStartupFailure() throws {
        let vmName = "nonexistent-vm-\(UUID().uuidString)"
        
        // Attempt to start non-existent VM should fail
        XCTAssertThrowsError(try vmManager.startVM(name: vmName)) { error in
            XCTAssertTrue(error is QEMUVMManagerError)
            if let vmError = error as? QEMUVMManagerError {
                switch vmError {
                case .vmNotFound(let missingName):
                    XCTAssertEqual(missingName, vmName)
                default:
                    XCTFail("Expected vmNotFound error, got \(vmError)")
                }
            }
        }
    }
    
    func testVMShutdown() throws {
        let vmName = "shutdown-vm-\(UUID().uuidString)"
        
        // Create and start VM
        let createResult = try vmManager.createVM(name: vmName)
        XCTAssertTrue(createResult.success)
        
        let startResult = try vmManager.startVM(name: vmName)
        XCTAssertTrue(startResult.success)
        
        // Stop VM
        let stopResult = try vmManager.stopVM(name: vmName, graceful: true)
        XCTAssertTrue(stopResult.success, "VM shutdown should succeed")
        XCTAssertEqual(stopResult.vmName, vmName)
        
        // Verify VM is stopped
        let status = try vmManager.getVMStatus(name: vmName)
        XCTAssertEqual(status.state, .stopped)
    }
    
    func testVMForcedShutdown() throws {
        let vmName = "forced-shutdown-vm-\(UUID().uuidString)"
        
        // Create and start VM
        _ = try vmManager.createVM(name: vmName)
        _ = try vmManager.startVM(name: vmName)
        
        // Force stop VM (simulates unresponsive VM)
        let stopResult = try vmManager.stopVM(name: vmName, graceful: false)
        XCTAssertTrue(stopResult.success, "Forced VM shutdown should succeed")
        
        // Verify VM is stopped
        let status = try vmManager.getVMStatus(name: vmName)
        XCTAssertEqual(status.state, .stopped)
    }
    
    func testVMCleanup() throws {
        let vmName = "cleanup-vm-\(UUID().uuidString)"
        
        // Create VM
        let createResult = try vmManager.createVM(name: vmName)
        XCTAssertTrue(createResult.success)
        
        // Verify VM exists
        XCTAssertTrue(try vmManager.vmExists(name: vmName))
        
        // Clean up VM
        let cleanupResult = try vmManager.cleanupVM(name: vmName)
        XCTAssertTrue(cleanupResult.success, "VM cleanup should succeed")
        XCTAssertEqual(cleanupResult.vmName, vmName)
        
        // Verify VM no longer exists
        XCTAssertFalse(try vmManager.vmExists(name: vmName))
    }
    
    // MARK: - Error Scenario Tests
    
    func testInsufficientDiskSpace() throws {
        // Mock insufficient disk space scenario
        vmManager.simulateInsufficientDiskSpace = true
        
        let vmName = "disk-space-vm-\(UUID().uuidString)"
        
        XCTAssertThrowsError(try vmManager.createVM(name: vmName)) { error in
            XCTAssertTrue(error is QEMUVMManagerError)
            if let vmError = error as? QEMUVMManagerError {
                switch vmError {
                case .insufficientResources(let resource):
                    XCTAssertEqual(resource, "disk_space")
                default:
                    XCTFail("Expected insufficientResources error, got \(vmError)")
                }
            }
        }
    }
    
    func testQEMUProcessFailure() throws {
        let vmName = "process-failure-vm-\(UUID().uuidString)"
        
        // Create VM
        _ = try vmManager.createVM(name: vmName)
        
        // Simulate QEMU process failure
        vmManager.simulateProcessFailure = true
        
        XCTAssertThrowsError(try vmManager.startVM(name: vmName)) { error in
            XCTAssertTrue(error is QEMUVMManagerError)
            if let vmError = error as? QEMUVMManagerError {
                switch vmError {
                case .processStartupFailure(let reason):
                    XCTAssertTrue(reason.contains("simulated failure"))
                default:
                    XCTFail("Expected processStartupFailure error, got \(vmError)")
                }
            }
        }
    }
    
    func testNetworkPortConflict() throws {
        let vmName1 = "port-conflict-vm1-\(UUID().uuidString)"
        let vmName2 = "port-conflict-vm2-\(UUID().uuidString)"
        
        // Create first VM
        _ = try vmManager.createVM(name: vmName1)
        let startResult1 = try vmManager.startVM(name: vmName1)
        XCTAssertTrue(startResult1.success)
        
        // Create second VM
        _ = try vmManager.createVM(name: vmName2)
        
        // Simulate port conflict
        vmManager.simulatePortConflict = true
        
        XCTAssertThrowsError(try vmManager.startVM(name: vmName2)) { error in
            XCTAssertTrue(error is QEMUVMManagerError)
            if let vmError = error as? QEMUVMManagerError {
                switch vmError {
                case .networkConfigurationFailure(let reason):
                    XCTAssertTrue(reason.contains("port") || reason.contains("conflict"))
                default:
                    XCTFail("Expected networkConfigurationFailure error, got \(vmError)")
                }
            }
        }
    }
    
    // MARK: - Performance Tests
    
    func testVMStartupPerformance() throws {
        let vmName = "performance-vm-\(UUID().uuidString)"
        _ = try vmManager.createVM(name: vmName)
        
        let timeout = environmentConfig.environment.executionTimeLimit
        
        // Measure VM startup time
        measure {
            do {
                _ = try vmManager.startVM(name: vmName)
                _ = try vmManager.stopVM(name: vmName, graceful: false)
            } catch {
                XCTFail("VM startup failed: \(error)")
            }
        }
    }
    
    func testMultipleVMManagement() throws {
        let vmCount = 2 // Keep it simple for testing
        var vmNames: [String] = []
        
        // Create multiple VMs
        for i in 0..<vmCount {
            let vmName = "multi-vm-\(i)-\(UUID().uuidString)"
            vmNames.append(vmName)
            
            let createResult = try vmManager.createVM(name: vmName)
            XCTAssertTrue(createResult.success, "VM \(i) creation should succeed")
        }
        
        // Start all VMs
        for vmName in vmNames {
            let startResult = try vmManager.startVM(name: vmName)
            XCTAssertTrue(startResult.success, "VM \(vmName) startup should succeed")
        }
        
        // Verify all VMs are running
        for vmName in vmNames {
            let status = try vmManager.getVMStatus(name: vmName)
            XCTAssertEqual(status.state, .running, "VM \(vmName) should be running")
        }
        
        // Stop all VMs
        for vmName in vmNames {
            let stopResult = try vmManager.stopVM(name: vmName, graceful: true)
            XCTAssertTrue(stopResult.success, "VM \(vmName) shutdown should succeed")
        }
        
        // Clean up all VMs
        for vmName in vmNames {
            let cleanupResult = try vmManager.cleanupVM(name: vmName)
            XCTAssertTrue(cleanupResult.success, "VM \(vmName) cleanup should succeed")
        }
    }
    
    // MARK: - Integration Tests
    
    func testQEMUTestServerIntegration() throws {
        // Skip if we don't have QEMU capabilities
        guard hasQEMUCapability else {
            throw XCTSkip("QEMU integration test requires QEMU capabilities")
        }
        
        let vmName = "server-integration-vm-\(UUID().uuidString)"
        
        // Create and start VM
        _ = try vmManager.createVM(name: vmName)
        let startResult = try vmManager.startVM(name: vmName)
        XCTAssertTrue(startResult.success)
        
        // Test QEMUTestServer configuration integration
        let serverConfig = try testConfiguration.getTestServerConfiguration()
        XCTAssertEqual(serverConfig.port, 3240) // Default USB/IP port
        XCTAssertGreaterThan(serverConfig.maxConnections, 0)
        XCTAssertGreaterThan(serverConfig.requestTimeout, 0)
        
        // Cleanup
        _ = try vmManager.stopVM(name: vmName, graceful: true)
        _ = try vmManager.cleanupVM(name: vmName)
    }
}

// MARK: - Mock QEMU VM Manager

/// Mock implementation of QEMU VM Manager for testing
class MockQEMUVMManager {
    
    private let logger: Logger
    private let configuration: QEMUTestConfiguration
    private var managedVMs: [String: MockVMState] = [:]
    private var nextProcessId: Int32 = 12345
    private var nextPort: Int = 5555
    
    // Simulation flags for error scenarios
    var simulateInsufficientDiskSpace = false
    var simulateProcessFailure = false
    var simulatePortConflict = false
    
    init(logger: Logger, configuration: QEMUTestConfiguration) {
        self.logger = logger
        self.configuration = configuration
    }
    
    func createVM(name: String) throws -> VMCreationResult {
        logger.debug("Creating VM: \(name)")
        
        // Check for duplicate name
        if managedVMs[name] != nil {
            throw QEMUVMManagerError.vmAlreadyExists(name)
        }
        
        // Simulate insufficient disk space
        if simulateInsufficientDiskSpace {
            throw QEMUVMManagerError.insufficientResources("disk_space")
        }
        
        // Create mock VM state
        let vmState = MockVMState(
            name: name,
            state: .stopped,
            imagePath: "/tmp/qemu-test/\(name).qcow2",
            configPath: "/tmp/qemu-test/\(name).json"
        )
        
        managedVMs[name] = vmState
        logger.info("VM created successfully: \(name)")
        
        return VMCreationResult(
            success: true,
            vmName: name,
            imagePath: vmState.imagePath,
            configPath: vmState.configPath
        )
    }
    
    func startVM(name: String) throws -> VMStartupResult {
        logger.debug("Starting VM: \(name)")
        
        guard let vmState = managedVMs[name] else {
            throw QEMUVMManagerError.vmNotFound(name)
        }
        
        // Simulate process failure
        if simulateProcessFailure {
            throw QEMUVMManagerError.processStartupFailure("Simulated QEMU process startup failure")
        }
        
        // Simulate port conflict
        if simulatePortConflict {
            throw QEMUVMManagerError.networkConfigurationFailure("Simulated network port conflict")
        }
        
        // Update VM state
        vmState.state = .running
        vmState.processId = nextProcessId
        vmState.managementPort = nextPort
        vmState.startTime = Date()
        
        nextProcessId += 1
        nextPort += 1
        
        logger.info("VM started successfully: \(name)")
        
        return VMStartupResult(
            success: true,
            vmName: name,
            processId: vmState.processId,
            managementPort: vmState.managementPort
        )
    }
    
    func stopVM(name: String, graceful: Bool) throws -> VMShutdownResult {
        logger.debug("Stopping VM: \(name) (graceful: \(graceful))")
        
        guard let vmState = managedVMs[name] else {
            throw QEMUVMManagerError.vmNotFound(name)
        }
        
        // Update VM state
        vmState.state = .stopped
        vmState.processId = nil
        vmState.managementPort = nil
        vmState.startTime = nil
        
        logger.info("VM stopped successfully: \(name)")
        
        return VMShutdownResult(
            success: true,
            vmName: name,
            graceful: graceful
        )
    }
    
    func cleanupVM(name: String) throws -> VMCleanupResult {
        logger.debug("Cleaning up VM: \(name)")
        
        guard managedVMs[name] != nil else {
            throw QEMUVMManagerError.vmNotFound(name)
        }
        
        // Remove VM from management
        managedVMs.removeValue(forKey: name)
        
        logger.info("VM cleaned up successfully: \(name)")
        
        return VMCleanupResult(
            success: true,
            vmName: name
        )
    }
    
    func vmExists(name: String) throws -> Bool {
        return managedVMs[name] != nil
    }
    
    func getVMStatus(name: String) throws -> VMStatus {
        guard let vmState = managedVMs[name] else {
            throw QEMUVMManagerError.vmNotFound(name)
        }
        
        let uptime = vmState.startTime?.timeIntervalSinceNow.magnitude
        
        return VMStatus(
            vmName: name,
            state: vmState.state,
            processId: vmState.processId,
            managementPort: vmState.managementPort,
            uptime: uptime
        )
    }
}

// MARK: - Mock Data Structures

class MockVMState {
    let name: String
    var state: VMState
    let imagePath: String
    let configPath: String
    var processId: Int32?
    var managementPort: Int?
    var startTime: Date?
    
    init(name: String, state: VMState, imagePath: String, configPath: String) {
        self.name = name
        self.state = state
        self.imagePath = imagePath
        self.configPath = configPath
    }
}

// MARK: - Result Types

struct VMCreationResult {
    let success: Bool
    let vmName: String
    let imagePath: String
    let configPath: String
}

struct VMStartupResult {
    let success: Bool
    let vmName: String
    let processId: Int32?
    let managementPort: Int?
}

struct VMShutdownResult {
    let success: Bool
    let vmName: String
    let graceful: Bool
}

struct VMCleanupResult {
    let success: Bool
    let vmName: String
}

struct VMStatus {
    let vmName: String
    let state: VMState
    let processId: Int32?
    let managementPort: Int?
    let uptime: TimeInterval?
}

// MARK: - VM State Enum

enum VMState {
    case stopped
    case starting
    case running
    case stopping
    case error
}

// MARK: - Error Types

enum QEMUVMManagerError: Error, LocalizedError {
    case vmNotFound(String)
    case vmAlreadyExists(String)
    case insufficientResources(String)
    case processStartupFailure(String)
    case networkConfigurationFailure(String)
    case configurationError(String)
    
    var errorDescription: String? {
        switch self {
        case .vmNotFound(let name):
            return "VM not found: \(name)"
        case .vmAlreadyExists(let name):
            return "VM already exists: \(name)"
        case .insufficientResources(let resource):
            return "Insufficient resources: \(resource)"
        case .processStartupFailure(let reason):
            return "Process startup failure: \(reason)"
        case .networkConfigurationFailure(let reason):
            return "Network configuration failure: \(reason)"
        case .configurationError(let reason):
            return "Configuration error: \(reason)"
        }
    }
}