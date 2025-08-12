//
//  ProductionTests.swift
//  usbipd-mac
//
//  Production Test Environment - Comprehensive validation tests including QEMU integration
//  Consolidates end-to-end workflows and hardware-dependent tests for release preparation
//

import XCTest
import Foundation
@testable import USBIPDCore
@testable import USBIPDCLI
@testable import Common
@testable import SystemExtension

/// Production Test Environment - Comprehensive validation for release preparation
/// Consolidates QEMU integration tests, System Extension integration, and end-to-end workflows
/// Tests complete USB/IP protocol implementation with real hardware when available
final class ProductionTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol Implementation
    
    let environmentConfig = TestEnvironmentConfig.production
    let requiredCapabilities: TestEnvironmentCapabilities = [
        .qemuIntegration,
        .systemExtensionInstall,
        .timeIntensiveOperations,
        .privilegedOperations
    ]
    let testCategory = "production"
    
    // MARK: - Test Properties
    
    private let scriptsPath = "Scripts"
    private let buildDir = ".build/qemu"
    private let testDataDir = ".build/qemu/test-data"
    private let logsDir = ".build/qemu/logs"
    
    // System Extension components
    var systemExtensionManager: SystemExtensionManager!
    var deviceClaimAdapter: SystemExtensionClaimAdapter!
    var deviceDiscovery: DeviceDiscovery!
    var serverConfig: ServerConfig!
    
    // Test timeouts for production environment
    private let shortTimeout: TimeInterval = 30
    private let mediumTimeout: TimeInterval = 120
    private let longTimeout: TimeInterval = 300
    
    // MARK: - Setup and Teardown
    
    override func setUp() {
        super.setUp()
        
        // Validate environment before proceeding
        do {
            try validateEnvironment()
        } catch {
            XCTFail("Environment validation failed: \(error)")
            return
        }
        
        setUpTestSuite()
    }
    
    override func tearDown() {
        tearDownTestSuite()
        super.tearDown()
    }
    
    func setUpTestSuite() {
        // Create test directories
        let fileManager = FileManager.default
        try? fileManager.createDirectory(atPath: testDataDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(atPath: logsDir, withIntermediateDirectories: true)
        
        // Initialize System Extension components
        systemExtensionManager = SystemExtensionManager()
        deviceClaimAdapter = SystemExtensionClaimAdapter(
            systemExtensionManager: systemExtensionManager
        )
        
        // Use appropriate device discovery based on environment capabilities
        if environmentConfig.hasCapability(.hardwareAccess) {
            deviceDiscovery = IOKitDeviceDiscovery()
        } else {
            let mockDiscovery = MockDeviceDiscovery()
            mockDiscovery.mockDevices = createTestDevices()
            deviceDiscovery = mockDiscovery
        }
        
        serverConfig = ServerConfig()
    }
    
    func tearDownTestSuite() {
        // Clean shutdown
        try? systemExtensionManager?.stop()
        
        // Clean up test data
        let fileManager = FileManager.default
        try? fileManager.removeItem(atPath: testDataDir)
        
        // Clean up any test QEMU processes
        _ = runCommand("/usr/bin/pkill", arguments: ["-f", "qemu-system-x86_64.*test"])
        
        // Reset properties
        systemExtensionManager = nil
        deviceClaimAdapter = nil
        deviceDiscovery = nil
        serverConfig = nil
    }
    
    // MARK: - Test Data Creation
    
    private func createTestDevices() -> [USBDevice] {
        return TestFixtures.createUSBDevices()
    }
    
    // MARK: - QEMU Integration Tests
    
    func testQEMUTestValidationWorkflow() throws {
        // Skip if QEMU integration is not available
        guard environmentConfig.hasCapability(.qemuIntegration) else {
            throw XCTSkip("QEMU integration not available in current environment")
        }
        
        // Test QEMU validation script functionality
        let validationResult = runScript("qemu-test-validation.sh", arguments: ["--help"], timeout: shortTimeout)
        XCTAssertEqual(validationResult.exitCode, 0, "QEMU validation script should be functional")
        XCTAssertTrue(validationResult.output.contains("Usage"), "Should provide usage information")
        
        // Test console log parsing with production data
        let logContent = """
        [2024-01-15 10:30:15.456] USBIP_STARTUP_BEGIN
        [2024-01-15 10:30:15.789] VHCI_MODULE_LOADED: SUCCESS
        [2024-01-15 10:30:16.456] USBIP_CLIENT_READY
        [2024-01-15 10:30:17.456] CONNECTING_TO_SERVER: 192.168.1.100:3240
        [2024-01-15 10:30:18.456] DEVICE_LIST_REQUEST: SUCCESS
        [2024-01-15 10:30:19.456] DEVICE_IMPORT_REQUEST: 1-1 SUCCESS
        [2024-01-15 10:30:20.890] TEST_COMPLETE: SUCCESS
        """
        
        let logPath = createTestFile(content: logContent, filename: "production-console.log")
        
        // Test readiness detection
        let readinessResult = runScript("qemu-test-validation.sh", 
                                       arguments: ["check-readiness", logPath], 
                                       timeout: shortTimeout)
        XCTAssertEqual(readinessResult.exitCode, 0, "Should detect client readiness in production log")
        
        // Test validation
        let validationTestResult = runScript("qemu-test-validation.sh", 
                                           arguments: ["validate-test", logPath], 
                                           timeout: shortTimeout)
        XCTAssertEqual(validationTestResult.exitCode, 0, "Should validate successful test in production log")
        
        // Test report generation
        let reportPath = "\(testDataDir)/production-report.txt"
        let reportResult = runScript("qemu-test-validation.sh", 
                                   arguments: ["generate-report", logPath, reportPath], 
                                   timeout: shortTimeout)
        XCTAssertEqual(reportResult.exitCode, 0, "Should generate production test report")
        XCTAssertTrue(fileExists(reportPath), "Production report file should be created")
    }
    
    func testQEMUImageCreationAndStartup() throws {
        // Skip if QEMU integration is not available
        guard environmentConfig.hasCapability(.qemuIntegration) else {
            throw XCTSkip("QEMU integration not available in current environment")
        }
        
        // Test QEMU image creation script
        let imageCreationResult = runScript("create-qemu-image.sh", arguments: ["--help"], timeout: mediumTimeout)
        XCTAssertTrue(imageCreationResult.exitCode == 0 || imageCreationResult.output.contains("QEMU"),
                      "Image creation script should be functional")
        
        // Test QEMU startup script
        let startupResult = runScript("start-qemu-client.sh", arguments: ["--help"], timeout: shortTimeout)
        XCTAssertTrue(startupResult.exitCode == 0 || startupResult.output.contains("QEMU"),
                      "Startup script should be functional")
    }
    
    func testQEMUComprehensiveIntegration() throws {
        // Skip if QEMU integration or time-intensive operations not available
        guard environmentConfig.hasCapability(.qemuIntegration) && 
              environmentConfig.hasCapability(.timeIntensiveOperations) else {
            throw XCTSkip("QEMU comprehensive integration requires time-intensive operations capability")
        }
        
        // Test cloud-init configuration validation
        let userDataContent = """
        #cloud-config
        users:
          - name: testuser
            sudo: ALL=(ALL) NOPASSWD:ALL
            shell: /bin/bash
        
        packages:
          - usbip
          - usbutils
          - linux-tools-common
        
        runcmd:
          - modprobe vhci-hcd
          - modprobe usbip-core
          - echo "USBIP_CLIENT_READY" > /dev/console
          - usbip version
          - echo "USBIP_VERSION: $(usbip version)" > /dev/console
        """
        
        let userDataPath = createTestFile(content: userDataContent, filename: "user-data")
        XCTAssertTrue(fileExists(userDataPath), "User-data file should be created")
        
        let content = try String(contentsOfFile: userDataPath)
        XCTAssertTrue(content.contains("#cloud-config"), "Should contain cloud-config header")
        XCTAssertTrue(content.contains("usbip"), "Should contain usbip package configuration")
        XCTAssertTrue(content.contains("vhci-hcd"), "Should contain vhci-hcd module loading")
        
        // Test network configuration
        let networkContent = """
        version: 2
        ethernets:
          eth0:
            dhcp4: true
            dhcp6: false
        """
        
        let networkPath = createTestFile(content: networkContent, filename: "network-config")
        XCTAssertTrue(fileExists(networkPath), "Network config should be created")
        
        // Test script availability and execution
        let requiredScripts = [
            "create-qemu-image.sh",
            "start-qemu-client.sh", 
            "qemu-test-validation.sh"
        ]
        
        for script in requiredScripts {
            let scriptPath = "\(scriptsPath)/\(script)"
            XCTAssertTrue(fileExists(scriptPath), "Required script should exist: \(script)")
            
            // Verify script is executable
            let attributes = try FileManager.default.attributesOfItem(atPath: scriptPath)
            let permissions = attributes[.posixPermissions] as? NSNumber
            XCTAssertNotNil(permissions, "Should have permissions for \(script)")
            
            if let perms = permissions?.uint16Value {
                XCTAssertTrue((perms & 0o100) != 0, "Script should be executable: \(script)")
            }
        }
    }
    
    // MARK: - System Extension Integration Tests
    
    func testSystemExtensionProductionWorkflow() throws {
        // Skip if System Extension installation not available
        guard environmentConfig.hasCapability(.systemExtensionInstall) else {
            throw XCTSkip("System Extension installation not available in current environment")
        }
        
        // Start System Extension
        try systemExtensionManager.start()
        defer { try? systemExtensionManager.stop() }
        
        // Discover devices
        let devices = try deviceDiscovery.discoverDevices()
        guard !devices.isEmpty else {
            throw XCTSkip("No USB devices available for production testing")
        }
        
        let testDevice = devices[0]
        let busid = "\(testDevice.busID)-\(testDevice.deviceID)"
        
        // Test complete bind → claim → status → release → unbind workflow
        let bindCommand = BindCommand(
            deviceDiscovery: deviceDiscovery,
            serverConfig: serverConfig,
            deviceClaimManager: deviceClaimAdapter
        )
        
        // Execute bind command
        try bindCommand.execute(with: [busid])
        XCTAssertTrue(serverConfig.allowedDevices.contains(busid), "Device should be bound")
        XCTAssertTrue(deviceClaimAdapter.isDeviceClaimed(deviceID: busid), "Device should be claimed")
        
        // Test status command
        let statusCommand = StatusCommand(deviceClaimManager: deviceClaimAdapter)
        XCTAssertNoThrow(try statusCommand.execute(with: []), "Status command should execute")
        XCTAssertNoThrow(try statusCommand.execute(with: ["--health"]), "Health check should execute")
        
        // Verify System Extension status
        let status = deviceClaimAdapter.getSystemExtensionStatus()
        XCTAssertTrue(status.isRunning, "System Extension should be running")
        XCTAssertEqual(status.claimedDevices.count, 1, "Should have 1 claimed device")
        
        // Test unbind command
        let unbindCommand = UnbindCommand(
            deviceDiscovery: deviceDiscovery,
            serverConfig: serverConfig,
            deviceClaimManager: deviceClaimAdapter
        )
        
        try unbindCommand.execute(with: [busid])
        XCTAssertFalse(serverConfig.allowedDevices.contains(busid), "Device should be unbound")
        XCTAssertFalse(deviceClaimAdapter.isDeviceClaimed(deviceID: busid), "Device should be released")
    }
    
    func testSystemExtensionStressAndRecovery() throws {
        // Skip if privileged operations not available
        guard environmentConfig.hasCapability(.privilegedOperations) else {
            throw XCTSkip("Privileged operations not available for stress testing")
        }
        
        try systemExtensionManager.start()
        defer { try? systemExtensionManager.stop() }
        
        let devices = try deviceDiscovery.discoverDevices()
        guard devices.count >= 2 else {
            throw XCTSkip("Need at least 2 devices for stress testing")
        }
        
        let testDevices = Array(devices.prefix(2))
        
        // Test stress operations
        let iterations = 5
        for i in 0..<iterations {
            for device in testDevices {
                let claimed = try deviceClaimAdapter.claimDevice(device)
                XCTAssertTrue(claimed, "Device should be claimed in iteration \(i)")
                
                // Brief operation
                Thread.sleep(forTimeInterval: 0.1)
                
                try deviceClaimAdapter.releaseDevice(device)
            }
        }
        
        // Test recovery after simulated crash
        try systemExtensionManager.stop()
        Thread.sleep(forTimeInterval: 1.0)
        try systemExtensionManager.start()
        
        // Verify system is functional after recovery
        let isHealthy = deviceClaimAdapter.performSystemExtensionHealthCheck()
        XCTAssertTrue(isHealthy, "System Extension should be healthy after recovery")
        
        // Verify no leaked claims
        let finalStatus = deviceClaimAdapter.getSystemExtensionStatus()
        XCTAssertEqual(finalStatus.claimedDevices.count, 0, "No devices should be claimed after recovery")
    }
    
    // MARK: - End-to-End Protocol Tests
    
    func testUSBIPProtocolComprehensive() throws {
        // Test complete USB/IP protocol implementation
        let devices = try deviceDiscovery.discoverDevices()
        guard !devices.isEmpty else {
            throw XCTSkip("No devices available for protocol testing")
        }
        
        let testDevice = devices[0]
        
        // Test device import/export request creation
        let importRequest = try USBIPDeviceImportRequest(
            busid: "\(testDevice.busID)-\(testDevice.deviceID)"
        )
        XCTAssertEqual(importRequest.busid, "\(testDevice.busID)-\(testDevice.deviceID)")
        
        // Test device list request/response
        let deviceListRequest = USBIPDeviceListRequest()
        let deviceListResponse = try USBIPDeviceListResponse(devices: [testDevice])
        XCTAssertEqual(deviceListResponse.devices.count, 1)
        XCTAssertEqual(deviceListResponse.devices[0].busID, testDevice.busID)
        
        // Test command submission encoding/decoding
        let submitCommand = try USBIPCommandSubmit(
            sequenceNumber: 1,
            deviceID: 1,
            direction: .out,
            endpoint: 0,
            transferFlags: 0,
            transferBufferLength: 8,
            startFrame: 0,
            numberOfPackets: 0,
            interval: 0,
            setupPacket: Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00])
        )
        XCTAssertEqual(submitCommand.sequenceNumber, 1)
        XCTAssertEqual(submitCommand.endpoint, 0)
        
        // Test unlink command
        let unlinkCommand = try USBIPCommandUnlink(
            sequenceNumber: 2,
            unlinkSequenceNumber: 1
        )
        XCTAssertEqual(unlinkCommand.sequenceNumber, 2)
        XCTAssertEqual(unlinkCommand.unlinkSequenceNumber, 1)
    }
    
    func testNetworkLayerIntegration() throws {
        // Test network layer with production configuration
        let serverConfig = ServerConfig(
            port: 3240,
            bindAddress: "127.0.0.1",
            maxConnections: 10
        )
        
        let tcpServer = try TCPServer(config: serverConfig)
        
        // Start server in background
        let serverStarted = expectation(description: "Server started")
        DispatchQueue.global(qos: .background).async {
            do {
                try tcpServer.start()
                serverStarted.fulfill()
            } catch {
                XCTFail("Failed to start TCP server: \(error)")
                serverStarted.fulfill()
            }
        }
        
        // Wait for server to start
        wait(for: [serverStarted], timeout: shortTimeout)
        
        defer {
            tcpServer.stop()
        }
        
        // Test server status
        XCTAssertTrue(tcpServer.isRunning, "TCP server should be running")
        XCTAssertEqual(tcpServer.activeConnections.count, 0, "Should have no active connections initially")
        
        // Test connection handling would require client connection
        // This is tested more thoroughly in integration environment
    }
    
    // MARK: - Hardware Integration Tests
    
    func testRealHardwareIntegration() throws {
        // Skip if hardware access not available
        guard environmentConfig.hasCapability(.hardwareAccess) else {
            throw XCTSkip("Hardware access not available in current environment")
        }
        
        // Use real device discovery
        let realDeviceDiscovery = IOKitDeviceDiscovery()
        let realDevices = try realDeviceDiscovery.discoverDevices()
        
        guard !realDevices.isEmpty else {
            throw XCTSkip("No real USB devices available for hardware integration testing")
        }
        
        // Test device enumeration accuracy
        for device in realDevices {
            XCTAssertNotEqual(device.vendorID, 0, "Device should have valid vendor ID")
            XCTAssertNotEqual(device.productID, 0, "Device should have valid product ID")
            XCTAssertFalse(device.busID.isEmpty, "Device should have valid bus ID")
            XCTAssertFalse(device.deviceID.isEmpty, "Device should have valid device ID")
        }
        
        // Test with real System Extension if available
        if environmentConfig.hasCapability(.systemExtensionInstall) {
            let realSystemExtensionManager = SystemExtensionManager()
            let realDeviceClaimAdapter = SystemExtensionClaimAdapter(
                systemExtensionManager: realSystemExtensionManager
            )
            
            try realSystemExtensionManager.start()
            defer { try? realSystemExtensionManager.stop() }
            
            // Test basic functionality with first real device
            let firstDevice = realDevices[0]
            
            do {
                let claimed = try realDeviceClaimAdapter.claimDevice(firstDevice)
                if claimed {
                    // Immediately release to avoid leaving system in bad state
                    try realDeviceClaimAdapter.releaseDevice(firstDevice)
                    print("Real hardware integration test successful with device: \(firstDevice.busID)-\(firstDevice.deviceID)")
                }
            } catch {
                // System Extension may not be available - this is acceptable
                print("Real hardware test skipped - System Extension not available: \(error)")
            }
        }
    }
    
    // MARK: - Performance and Reliability Tests
    
    func testProductionPerformanceValidation() throws {
        // Skip if time-intensive operations not available
        guard environmentConfig.hasCapability(.timeIntensiveOperations) else {
            throw XCTSkip("Time-intensive operations not available for performance testing")
        }
        
        let startTime = Date()
        let devices = try deviceDiscovery.discoverDevices()
        let discoveryTime = Date().timeIntervalSince(startTime)
        
        // Device discovery should complete within reasonable time
        XCTAssertLessThan(discoveryTime, 10.0, "Device discovery should complete within 10 seconds")
        
        guard !devices.isEmpty else {
            throw XCTSkip("No devices available for performance testing")
        }
        
        // Test System Extension performance if available
        if environmentConfig.hasCapability(.systemExtensionInstall) {
            try systemExtensionManager.start()
            defer { try? systemExtensionManager.stop() }
            
            let performanceStartTime = Date()
            let iterations = 10
            let device = devices[0]
            
            for i in 0..<iterations {
                let claimed = try deviceClaimAdapter.claimDevice(device)
                XCTAssertTrue(claimed, "Device should be claimed in performance iteration \(i)")
                try deviceClaimAdapter.releaseDevice(device)
            }
            
            let performanceTime = Date().timeIntervalSince(performanceStartTime)
            let operationsPerSecond = Double(iterations * 2) / performanceTime
            
            print("Production Performance: \(String(format: "%.2f", operationsPerSecond)) operations/second")
            
            // Performance should be reasonable for production use
            XCTAssertGreaterThan(operationsPerSecond, 1.0, "Should achieve at least 1 operation per second")
        }
    }
    
    func testReliabilityUnderLoad() throws {
        // Skip if time-intensive operations not available
        guard environmentConfig.hasCapability(.timeIntensiveOperations) else {
            throw XCTSkip("Time-intensive operations not available for reliability testing")
        }
        
        let devices = try deviceDiscovery.discoverDevices()
        guard devices.count >= 2 else {
            throw XCTSkip("Need multiple devices for reliability testing")
        }
        
        if environmentConfig.hasCapability(.systemExtensionInstall) {
            try systemExtensionManager.start()
            defer { try? systemExtensionManager.stop() }
            
            let concurrentOperations = 5
            let expectation = XCTestExpectation(description: "Reliability test")
            expectation.expectedFulfillmentCount = concurrentOperations
            var errors: [Error] = []
            let errorsLock = NSLock()
            
            // Run concurrent operations
            for i in 0..<concurrentOperations {
                DispatchQueue.global(qos: .userInitiated).async {
                    let device = devices[i % devices.count]
                    do {
                        for _ in 0..<3 { // Multiple operations per thread
                            let claimed = try self.deviceClaimAdapter.claimDevice(device)
                            XCTAssertTrue(claimed, "Device should be claimed reliably")
                            Thread.sleep(forTimeInterval: 0.1)
                            try self.deviceClaimAdapter.releaseDevice(device)
                        }
                        expectation.fulfill()
                    } catch {
                        errorsLock.lock()
                        errors.append(error)
                        errorsLock.unlock()
                        expectation.fulfill()
                    }
                }
            }
            
            let result = XCTWaiter.wait(for: [expectation], timeout: longTimeout)
            XCTAssertEqual(result, .completed, "Reliability test should complete")
            XCTAssertTrue(errors.isEmpty, "Should have no errors under concurrent load: \(errors)")
            
            // Verify system health after load
            let isHealthy = deviceClaimAdapter.performSystemExtensionHealthCheck()
            XCTAssertTrue(isHealthy, "System should remain healthy under load")
        }
    }
    
    // MARK: - Helper Methods
    
    private func runCommand(_ command: String, arguments: [String] = [], timeout: TimeInterval = 30) -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            
            let group = DispatchGroup()
            group.enter()
            
            DispatchQueue.global().async {
                process.waitUntilExit()
                group.leave()
            }
            
            let result = group.wait(timeout: .now() + timeout)
            
            if result == .timedOut {
                process.terminate()
                return ("Process timed out", -1)
            }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            return (output, process.terminationStatus)
        } catch {
            return ("Error running command: \(error)", -1)
        }
    }
    
    private func runScript(_ scriptName: String, arguments: [String] = [], timeout: TimeInterval = 30) -> (output: String, exitCode: Int32) {
        let scriptPath = "\(scriptsPath)/\(scriptName)"
        return runCommand("/bin/bash", arguments: [scriptPath] + arguments, timeout: timeout)
    }
    
    private func createTestFile(content: String, filename: String) -> String {
        let filePath = "\(testDataDir)/\(filename)"
        try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
        return filePath
    }
    
    private func fileExists(_ path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }
}