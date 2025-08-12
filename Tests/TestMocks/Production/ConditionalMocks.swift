//
//  ConditionalMocks.swift
//  usbipd-mac
//
//  Production Environment Conditional Mocks - Minimal mocking with hardware detection
//  Provides graceful degradation when hardware is unavailable while maintaining test coverage
//

import Foundation
import XCTest
@testable import USBIPDCore
@testable import USBIPDCLI
@testable import Common
@testable import SystemExtension

// MARK: - Hardware Detection

/// Hardware detection utilities for production testing
public struct HardwareDetector {
    
    /// Check if real USB hardware is available
    public static func hasUSBHardware() -> Bool {
        do {
            let realDeviceDiscovery = IOKitDeviceDiscovery()
            let devices = try realDeviceDiscovery.discoverDevices()
            return !devices.isEmpty
        } catch {
            return false
        }
    }
    
    /// Check if System Extension can be installed/activated
    public static func canUseSystemExtension() -> Bool {
        #if os(macOS)
        // Check for admin privileges or test environment variable
        if getuid() == 0 || ProcessInfo.processInfo.environment["TEST_ALLOW_SYSEXT"] != nil {
            return true
        }
        
        // Check if System Extension is already activated
        let systemExtensionManager = SystemExtensionManager()
        let status = systemExtensionManager.getStatus()
        return status.isRunning
        #else
        return false
        #endif
    }
    
    /// Check if QEMU is available and functional
    public static func hasQEMUCapability() -> Bool {
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
    
    /// Check if network operations are available
    public static func hasNetworkAccess() -> Bool {
        // Simple network connectivity check
        let host = "127.0.0.1"
        let port = 80
        
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor != -1 else { return false }
        defer { close(socketDescriptor) }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr(host)
        
        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        return connectResult == 0
    }
}

// MARK: - Conditional Device Discovery

/// Device discovery that gracefully falls back to mocks when hardware unavailable
public class ConditionalDeviceDiscovery: DeviceDiscovery {
    
    private let realDeviceDiscovery: IOKitDeviceDiscovery
    private let mockDeviceDiscovery: MockDeviceDiscovery
    private let preferReal: Bool
    
    public init(preferReal: Bool = true) {
        self.realDeviceDiscovery = IOKitDeviceDiscovery()
        self.mockDeviceDiscovery = MockDeviceDiscovery()
        self.preferReal = preferReal
        
        // Set up mock devices for fallback
        setupMockDevices()
    }
    
    private func setupMockDevices() {
        mockDeviceDiscovery.mockDevices = [
            // Production-grade test device - Mouse
            USBDevice(
                busID: "20",
                deviceID: "1",
                vendorID: 0x05ac,
                productID: 0x030d,
                deviceClass: 0x03,
                deviceSubClass: 0x01,
                deviceProtocol: 0x02,
                speed: .low,
                manufacturerString: "Apple Inc.",
                productString: "Magic Mouse",
                serialNumberString: "ABC123456789"
            ),
            
            // Production-grade test device - Storage
            USBDevice(
                busID: "21",
                deviceID: "1",
                vendorID: 0x0781,
                productID: 0x5567,
                deviceClass: 0x08,
                deviceSubClass: 0x06,
                deviceProtocol: 0x50,
                speed: .high,
                manufacturerString: "SanDisk Corp.",
                productString: "Cruzer Blade",
                serialNumberString: "4C530001071218115260"
            ),
            
            // Production-grade test device - Keyboard
            USBDevice(
                busID: "20",
                deviceID: "2",
                vendorID: 0x046d,
                productID: 0xc31c,
                deviceClass: 0x03,
                deviceSubClass: 0x01,
                deviceProtocol: 0x01,
                speed: .low,
                manufacturerString: "Logitech",
                productString: "USB Receiver",
                serialNumberString: "DEF987654321"
            )
        ]
    }
    
    public func discoverDevices() throws -> [USBDevice] {
        if preferReal && HardwareDetector.hasUSBHardware() {
            do {
                return try realDeviceDiscovery.discoverDevices()
            } catch {
                // Fall back to mock if real discovery fails
                print("Warning: Real device discovery failed, falling back to mocks: \(error)")
                return try mockDeviceDiscovery.discoverDevices()
            }
        } else {
            return try mockDeviceDiscovery.discoverDevices()
        }
    }
    
    public func startMonitoring() throws {
        if preferReal && HardwareDetector.hasUSBHardware() {
            try? realDeviceDiscovery.startMonitoring()
        }
        // Mock discovery doesn't need monitoring
    }
    
    public func stopMonitoring() {
        realDeviceDiscovery.stopMonitoring()
        // Mock discovery doesn't need monitoring
    }
    
    /// Get the underlying real discovery instance if available
    public var realDiscovery: IOKitDeviceDiscovery? {
        return HardwareDetector.hasUSBHardware() ? realDeviceDiscovery : nil
    }
    
    /// Get the mock discovery instance
    public var mockDiscovery: MockDeviceDiscovery {
        return mockDeviceDiscovery
    }
}

// MARK: - Conditional System Extension

/// System Extension manager that conditionally uses real or mock implementation
public class ConditionalSystemExtensionManager {
    
    private let realManager: SystemExtensionManager?
    private let mockManager: MockSystemExtensionManager
    private let canUseReal: Bool
    
    public init() {
        self.canUseReal = HardwareDetector.canUseSystemExtension()
        self.realManager = canUseReal ? SystemExtensionManager() : nil
        self.mockManager = MockSystemExtensionManager()
    }
    
    public func start() throws {
        if canUseReal, let real = realManager {
            try real.start()
        } else {
            try mockManager.start()
        }
    }
    
    public func stop() throws {
        if canUseReal, let real = realManager {
            try real.stop()
        } else {
            try mockManager.stop()
        }
    }
    
    public func restart() throws {
        if canUseReal, let real = realManager {
            try real.restart()
        } else {
            try mockManager.restart()
        }
    }
    
    public func getStatus() -> SystemExtensionStatus {
        if canUseReal, let real = realManager {
            return real.getStatus()
        } else {
            return mockManager.getStatus()
        }
    }
    
    /// Check if using real System Extension
    public var isUsingRealSystemExtension: Bool {
        return canUseReal && realManager != nil
    }
}

// MARK: - Conditional Device Claim Adapter

/// Device claim adapter that conditionally uses real or mock System Extension
public class ConditionalDeviceClaimAdapter: DeviceClaimManager {
    
    private let realAdapter: SystemExtensionClaimAdapter?
    private let mockAdapter: MockDeviceClaimManager
    private let conditionalManager: ConditionalSystemExtensionManager
    
    public init() {
        self.conditionalManager = ConditionalSystemExtensionManager()
        
        if conditionalManager.isUsingRealSystemExtension {
            self.realAdapter = SystemExtensionClaimAdapter(
                systemExtensionManager: conditionalManager.realManager!
            )
            self.mockAdapter = MockDeviceClaimManager()
        } else {
            self.realAdapter = nil
            self.mockAdapter = MockDeviceClaimManager()
        }
    }
    
    public func claimDevice(_ device: USBDevice) throws -> Bool {
        if let real = realAdapter {
            return try real.claimDevice(device)
        } else {
            return try mockAdapter.claimDevice(device)
        }
    }
    
    public func releaseDevice(_ device: USBDevice) throws {
        if let real = realAdapter {
            try real.releaseDevice(device)
        } else {
            try mockAdapter.releaseDevice(device)
        }
    }
    
    public func isDeviceClaimed(deviceID: String) -> Bool {
        if let real = realAdapter {
            return real.isDeviceClaimed(deviceID: deviceID)
        } else {
            return mockAdapter.isDeviceClaimed(deviceID: deviceID)
        }
    }
    
    public func getClaimedDevices() -> [String] {
        if let real = realAdapter {
            return real.getClaimedDevices()
        } else {
            return mockAdapter.getClaimedDevices()
        }
    }
    
    /// Get System Extension status
    public func getSystemExtensionStatus() -> SystemExtensionStatus {
        return conditionalManager.getStatus()
    }
    
    /// Perform health check
    public func performSystemExtensionHealthCheck() -> Bool {
        if let real = realAdapter {
            return real.performSystemExtensionHealthCheck()
        } else {
            // Mock always reports healthy
            return true
        }
    }
    
    /// Get statistics
    public func getSystemExtensionStatistics() -> SystemExtensionStatistics {
        if let real = realAdapter {
            return real.getSystemExtensionStatistics()
        } else {
            // Return mock statistics
            return SystemExtensionStatistics(
                successfulClaims: 1,
                failedClaims: 0,
                activeConnections: 0,
                uptime: 60.0
            )
        }
    }
    
    /// Check if using real System Extension
    public var isUsingRealSystemExtension: Bool {
        return realAdapter != nil
    }
}

// MARK: - Conditional TCP Server

/// TCP server that conditionally binds to real or mock network interfaces
public class ConditionalTCPServer: NetworkServer {
    
    private let realServer: TCPServer?
    private let mockServer: MockTCPServer
    private let canUseRealNetwork: Bool
    
    public init(config: ServerConfig) throws {
        self.canUseRealNetwork = HardwareDetector.hasNetworkAccess()
        
        if canUseRealNetwork {
            self.realServer = try TCPServer(config: config)
            self.mockServer = MockTCPServer(config: config)
        } else {
            self.realServer = nil
            self.mockServer = MockTCPServer(config: config)
        }
    }
    
    public func start() throws {
        if canUseRealNetwork, let real = realServer {
            try real.start()
        } else {
            try mockServer.start()
        }
    }
    
    public func stop() {
        if canUseRealNetwork, let real = realServer {
            real.stop()
        } else {
            mockServer.stop()
        }
    }
    
    public var isRunning: Bool {
        if canUseRealNetwork, let real = realServer {
            return real.isRunning
        } else {
            return mockServer.isRunning
        }
    }
    
    public var activeConnections: [ClientConnection] {
        if canUseRealNetwork, let real = realServer {
            return real.activeConnections
        } else {
            return mockServer.activeConnections
        }
    }
    
    /// Check if using real network
    public var isUsingRealNetwork: Bool {
        return canUseRealNetwork && realServer != nil
    }
}

// MARK: - Mock Implementations for Production Fallback

/// Mock System Extension Manager for production fallback
public class MockSystemExtensionManager {
    
    private var isStarted = false
    
    public init() {}
    
    public func start() throws {
        isStarted = true
    }
    
    public func stop() throws {
        isStarted = false
    }
    
    public func restart() throws {
        isStarted = false
        try start()
    }
    
    public func getStatus() -> SystemExtensionStatus {
        return SystemExtensionStatus(
            isRunning: isStarted,
            claimedDevices: [],
            lastError: nil
        )
    }
}

/// Mock Device Claim Manager for production fallback
public class MockDeviceClaimManager: DeviceClaimManager {
    
    private var claimedDevices: Set<String> = []
    
    public init() {}
    
    public func claimDevice(_ device: USBDevice) throws -> Bool {
        let deviceID = "\(device.busID)-\(device.deviceID)"
        claimedDevices.insert(deviceID)
        return true
    }
    
    public func releaseDevice(_ device: USBDevice) throws {
        let deviceID = "\(device.busID)-\(device.deviceID)"
        claimedDevices.remove(deviceID)
    }
    
    public func isDeviceClaimed(deviceID: String) -> Bool {
        return claimedDevices.contains(deviceID)
    }
    
    public func getClaimedDevices() -> [String] {
        return Array(claimedDevices)
    }
}

/// Mock TCP Server for production fallback
public class MockTCPServer: NetworkServer {
    
    private let config: ServerConfig
    private var isStarted = false
    private var mockConnections: [ClientConnection] = []
    
    public init(config: ServerConfig) {
        self.config = config
    }
    
    public func start() throws {
        isStarted = true
    }
    
    public func stop() {
        isStarted = false
        mockConnections.removeAll()
    }
    
    public var isRunning: Bool {
        return isStarted
    }
    
    public var activeConnections: [ClientConnection] {
        return mockConnections
    }
}

// MARK: - Production Test Utilities

/// Utilities for production testing with conditional hardware access
public struct ProductionTestUtilities {
    
    /// Create appropriate device discovery for production testing
    public static func createDeviceDiscovery() -> DeviceDiscovery {
        return ConditionalDeviceDiscovery(preferReal: true)
    }
    
    /// Create appropriate device claim manager for production testing
    public static func createDeviceClaimManager() -> ConditionalDeviceClaimAdapter {
        return ConditionalDeviceClaimAdapter()
    }
    
    /// Create appropriate TCP server for production testing
    public static func createTCPServer(config: ServerConfig) throws -> ConditionalTCPServer {
        return try ConditionalTCPServer(config: config)
    }
    
    /// Check if full hardware testing is available
    public static func isFullHardwareTestingAvailable() -> Bool {
        return HardwareDetector.hasUSBHardware() && 
               HardwareDetector.canUseSystemExtension() &&
               HardwareDetector.hasNetworkAccess()
    }
    
    /// Get hardware capabilities summary for reporting
    public static func getHardwareCapabilitiesSummary() -> [String: Bool] {
        return [
            "usb_hardware": HardwareDetector.hasUSBHardware(),
            "system_extension": HardwareDetector.canUseSystemExtension(),
            "qemu_capability": HardwareDetector.hasQEMUCapability(),
            "network_access": HardwareDetector.hasNetworkAccess()
        ]
    }
    
    /// Skip test with appropriate message if hardware requirement not met
    public static func skipTestIfHardwareUnavailable(
        requiring capability: String
    ) throws {
        let capabilities = getHardwareCapabilitiesSummary()
        
        switch capability {
        case "usb_hardware":
            if !capabilities["usb_hardware"]! {
                throw XCTSkip("USB hardware not available for testing")
            }
        case "system_extension":
            if !capabilities["system_extension"]! {
                throw XCTSkip("System Extension capabilities not available")
            }
        case "qemu_capability":
            if !capabilities["qemu_capability"]! {
                throw XCTSkip("QEMU not available for integration testing")
            }
        case "network_access":
            if !capabilities["network_access"]! {
                throw XCTSkip("Network access not available for testing")
            }
        case "full_hardware":
            if !isFullHardwareTestingAvailable() {
                throw XCTSkip("Full hardware testing capabilities not available")
            }
        default:
            break
        }
    }
}

// MARK: - Extensions for Test Reporting

extension ConditionalDeviceDiscovery {
    /// Get test report about which implementation is being used
    public func getImplementationReport() -> [String: Any] {
        return [
            "using_real_hardware": HardwareDetector.hasUSBHardware(),
            "real_devices_available": (try? realDeviceDiscovery.discoverDevices().count) ?? 0,
            "mock_devices_available": mockDeviceDiscovery.mockDevices.count
        ]
    }
}

extension ConditionalDeviceClaimAdapter {
    /// Get test report about System Extension usage
    public func getImplementationReport() -> [String: Any] {
        return [
            "using_real_system_extension": isUsingRealSystemExtension,
            "system_extension_available": HardwareDetector.canUseSystemExtension(),
            "claimed_devices_count": getClaimedDevices().count
        ]
    }
}

extension ConditionalTCPServer {
    /// Get test report about network implementation
    public func getImplementationReport() -> [String: Any] {
        return [
            "using_real_network": isUsingRealNetwork,
            "network_available": HardwareDetector.hasNetworkAccess(),
            "is_running": isRunning,
            "active_connections": activeConnections.count
        ]
    }
}