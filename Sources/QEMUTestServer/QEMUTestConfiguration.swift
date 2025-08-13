// QEMUTestConfiguration.swift
// Test configuration management for QEMU testing infrastructure

import Foundation
import Common

/// Test environment types supported by the QEMU test infrastructure
public enum TestEnvironment: String, CaseIterable, Codable {
    case development = "development"
    case ci = "ci"
    case production = "production"
    
    /// Detect test environment from system environment variables
    public static func detect() -> TestEnvironment {
        // Check CI environment indicators
        if ProcessInfo.processInfo.environment["CI"] != nil ||
           ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil {
            return .ci
        }
        
        // Check explicit TEST_ENVIRONMENT variable
        if let envString = ProcessInfo.processInfo.environment["TEST_ENVIRONMENT"],
           let environment = TestEnvironment(rawValue: envString) {
            return environment
        }
        
        // Check legacy PRODUCTION_TEST variable
        if ProcessInfo.processInfo.environment["PRODUCTION_TEST"] != nil {
            return .production
        }
        
        // Default to development
        return .development
    }
    
    /// Get human-readable description
    public var description: String {
        switch self {
        case .development:
            return "Development environment - fast feedback with minimal resources"
        case .ci:
            return "CI environment - automated testing optimized for GitHub Actions"
        case .production:
            return "Production environment - comprehensive validation with full resources"
        }
    }
    
    /// Get default timeout values for this environment
    public var defaultTimeouts: EnvironmentTimeouts {
        switch self {
        case .development:
            return EnvironmentTimeouts(
                readiness: 30,
                connection: 5,
                command: 15,
                boot: 30,
                shutdown: 10
            )
        case .ci:
            return EnvironmentTimeouts(
                readiness: 60,
                connection: 10,
                command: 30,
                boot: 60,
                shutdown: 30
            )
        case .production:
            return EnvironmentTimeouts(
                readiness: 120,
                connection: 15,
                command: 60,
                boot: 120,
                shutdown: 60
            )
        }
    }
}

/// Environment-specific timeout configuration
public struct EnvironmentTimeouts: Codable {
    public let readiness: TimeInterval
    public let connection: TimeInterval
    public let command: TimeInterval
    public let boot: TimeInterval
    public let shutdown: TimeInterval
    
    public init(readiness: TimeInterval, connection: TimeInterval, command: TimeInterval, boot: TimeInterval, shutdown: TimeInterval) {
        self.readiness = readiness
        self.connection = connection
        self.command = command
        self.boot = boot
        self.shutdown = shutdown
    }
}

/// VM configuration parameters
public struct VMConfiguration: Codable {
    public let memory: String
    public let cpuCores: Int
    public let diskSize: String
    public let enableKVM: Bool
    public let enableGraphics: Bool
    public let bootTimeout: TimeInterval
    public let shutdownTimeout: TimeInterval
    
    private enum CodingKeys: String, CodingKey {
        case memory
        case cpuCores = "cpu_cores"
        case diskSize = "disk_size"
        case enableKVM = "enable_kvm"
        case enableGraphics = "enable_graphics"
        case bootTimeout = "boot_timeout"
        case shutdownTimeout = "shutdown_timeout"
    }
}

/// Network port forwarding configuration
public struct PortForward: Codable {
    public let `protocol`: String
    public let hostPort: Int
    public let guestPort: Int
    public let description: String
    
    private enum CodingKeys: String, CodingKey {
        case `protocol` = "protocol"
        case hostPort = "host_port"
        case guestPort = "guest_port"
        case description
    }
}

/// Network configuration
public struct NetworkConfiguration: Codable {
    public let type: String
    public let hostForwards: [PortForward]
    
    private enum CodingKeys: String, CodingKey {
        case type
        case hostForwards = "host_forwards"
    }
}

/// Testing configuration parameters
public struct TestingConfiguration: Codable {
    public let maxTestDuration: TimeInterval
    public let enableHardwareTests: Bool
    public let enableSystemExtensionTests: Bool
    public let mockLevel: String
    public let parallelTests: Bool
    
    private enum CodingKeys: String, CodingKey {
        case maxTestDuration = "max_test_duration"
        case enableHardwareTests = "enable_hardware_tests"
        case enableSystemExtensionTests = "enable_system_extension_tests"
        case mockLevel = "mock_level"
        case parallelTests = "parallel_tests"
    }
}

/// Complete environment configuration
public struct EnvironmentConfiguration: Codable {
    public let description: String
    public let vm: VMConfiguration
    public let network: NetworkConfiguration
    public let testing: TestingConfiguration
    public let qemuArgs: [String]
    
    private enum CodingKeys: String, CodingKey {
        case description
        case vm
        case network
        case testing
        case qemuArgs = "qemu_args"
    }
}

/// QEMU test configuration manager
public class QEMUTestConfiguration {
    private let logger: Logger
    private let configurationPath: String
    private let currentEnvironment: TestEnvironment
    private var loadedConfiguration: EnvironmentConfiguration?
    
    /// Configuration file paths to search
    public static let defaultConfigPaths = [
        "Scripts/qemu/test-vm-config.json",
        "test-vm-config.json",
        ".qemu-config.json"
    ]
    
    /// Initialize configuration manager
    public init(logger: Logger, configPath: String? = nil, environment: TestEnvironment? = nil) {
        self.logger = logger
        self.currentEnvironment = environment ?? TestEnvironment.detect()
        
        // Find configuration file
        if let configPath = configPath {
            self.configurationPath = configPath
        } else {
            self.configurationPath = Self.findConfigurationFile() ?? Self.defaultConfigPaths[0]
        }
        
        logger.info("QEMUTestConfiguration initialized", context: [
            "environment": currentEnvironment.rawValue,
            "configPath": configurationPath
        ])
    }
    
    /// Find the first existing configuration file
    private static func findConfigurationFile() -> String? {
        let fileManager = FileManager.default
        
        for path in defaultConfigPaths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }
    
    /// Load configuration for current environment
    public func loadConfiguration() throws -> EnvironmentConfiguration {
        if let cached = loadedConfiguration {
            return cached
        }
        
        logger.info("Loading configuration", context: [
            "environment": currentEnvironment.rawValue,
            "configPath": configurationPath
        ])
        
        guard FileManager.default.fileExists(atPath: configurationPath) else {
            logger.warning("Configuration file not found, using defaults", context: [
                "configPath": configurationPath
            ])
            let defaultConfig = createDefaultConfiguration()
            loadedConfiguration = defaultConfig
            return defaultConfig
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configurationPath))
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            
            guard let configDict = json as? [String: Any],
                  let environments = configDict["environments"] as? [String: Any],
                  let envConfig = environments[currentEnvironment.rawValue] as? [String: Any] else {
                
                logger.warning("Invalid configuration format, using defaults")
                let defaultConfig = createDefaultConfiguration()
                loadedConfiguration = defaultConfig
                return defaultConfig
            }
            
            let envData = try JSONSerialization.data(withJSONObject: envConfig)
            let configuration = try JSONDecoder().decode(EnvironmentConfiguration.self, from: envData)
            
            logger.info("Configuration loaded successfully", context: [
                "environment": currentEnvironment.rawValue,
                "memory": configuration.vm.memory,
                "cpuCores": configuration.vm.cpuCores,
                "maxTestDuration": Int(configuration.testing.maxTestDuration)
            ])
            
            loadedConfiguration = configuration
            return configuration
            
        } catch {
            logger.error("Failed to load configuration", context: [
                "error": error.localizedDescription,
                "configPath": configurationPath
            ])
            
            let defaultConfig = createDefaultConfiguration()
            loadedConfiguration = defaultConfig
            return defaultConfig
        }
    }
    
    /// Create default configuration for current environment
    private func createDefaultConfiguration() -> EnvironmentConfiguration {
        logger.info("Creating default configuration", context: [
            "environment": currentEnvironment.rawValue
        ])
        
        let timeouts = currentEnvironment.defaultTimeouts
        
        switch currentEnvironment {
        case .development:
            return EnvironmentConfiguration(
                description: currentEnvironment.description,
                vm: VMConfiguration(
                    memory: "128M",
                    cpuCores: 1,
                    diskSize: "512M",
                    enableKVM: true,
                    enableGraphics: false,
                    bootTimeout: timeouts.boot,
                    shutdownTimeout: timeouts.shutdown
                ),
                network: NetworkConfiguration(
                    type: "user",
                    hostForwards: [
                        PortForward(protocol: "tcp", hostPort: 2222, guestPort: 22, description: "SSH access"),
                        PortForward(protocol: "tcp", hostPort: 3240, guestPort: 3240, description: "USB/IP protocol port")
                    ]
                ),
                testing: TestingConfiguration(
                    maxTestDuration: 60,
                    enableHardwareTests: false,
                    enableSystemExtensionTests: false,
                    mockLevel: "high",
                    parallelTests: true
                ),
                qemuArgs: ["-nographic", "-serial", "stdio", "-monitor", "none"]
            )
            
        case .ci:
            return EnvironmentConfiguration(
                description: currentEnvironment.description,
                vm: VMConfiguration(
                    memory: "256M",
                    cpuCores: 2,
                    diskSize: "1G",
                    enableKVM: false,
                    enableGraphics: false,
                    bootTimeout: timeouts.boot,
                    shutdownTimeout: timeouts.shutdown
                ),
                network: NetworkConfiguration(
                    type: "user",
                    hostForwards: [
                        PortForward(protocol: "tcp", hostPort: 2222, guestPort: 22, description: "SSH access"),
                        PortForward(protocol: "tcp", hostPort: 3240, guestPort: 3240, description: "USB/IP protocol port")
                    ]
                ),
                testing: TestingConfiguration(
                    maxTestDuration: 180,
                    enableHardwareTests: false,
                    enableSystemExtensionTests: false,
                    mockLevel: "medium",
                    parallelTests: true
                ),
                qemuArgs: ["-nographic", "-serial", "stdio", "-monitor", "none", "-no-reboot"]
            )
            
        case .production:
            return EnvironmentConfiguration(
                description: currentEnvironment.description,
                vm: VMConfiguration(
                    memory: "512M",
                    cpuCores: 4,
                    diskSize: "2G",
                    enableKVM: true,
                    enableGraphics: false,
                    bootTimeout: timeouts.boot,
                    shutdownTimeout: timeouts.shutdown
                ),
                network: NetworkConfiguration(
                    type: "user",
                    hostForwards: [
                        PortForward(protocol: "tcp", hostPort: 2222, guestPort: 22, description: "SSH access"),
                        PortForward(protocol: "tcp", hostPort: 3240, guestPort: 3240, description: "USB/IP protocol port"),
                        PortForward(protocol: "tcp", hostPort: 8080, guestPort: 80, description: "HTTP test server")
                    ]
                ),
                testing: TestingConfiguration(
                    maxTestDuration: 600,
                    enableHardwareTests: true,
                    enableSystemExtensionTests: true,
                    mockLevel: "low",
                    parallelTests: true
                ),
                qemuArgs: ["-nographic", "-serial", "stdio", "-monitor", "telnet:127.0.0.1:9001,server,nowait"]
            )
        }
    }
    
    /// Get current environment
    public func getCurrentEnvironment() -> TestEnvironment {
        return currentEnvironment
    }
    
    /// Get environment timeouts
    public func getTimeouts() -> EnvironmentTimeouts {
        return currentEnvironment.defaultTimeouts
    }
    
    /// Validate configuration
    public func validateConfiguration() throws {
        logger.info("Validating configuration", context: [
            "environment": currentEnvironment.rawValue
        ])
        
        let config = try loadConfiguration()
        
        // Validate VM configuration
        try validateVMConfiguration(config.vm)
        
        // Validate network configuration
        try validateNetworkConfiguration(config.network)
        
        // Validate testing configuration
        try validateTestingConfiguration(config.testing)
        
        logger.info("Configuration validation successful")
    }
    
    /// Validate VM configuration parameters
    private func validateVMConfiguration(_ vm: VMConfiguration) throws {
        // Validate memory format (should end with M, G, etc.)
        if !vm.memory.hasSuffix("M") && !vm.memory.hasSuffix("G") {
            throw ConfigurationError.invalidMemoryFormat(vm.memory)
        }
        
        // Validate CPU cores
        if vm.cpuCores < 1 || vm.cpuCores > 16 {
            throw ConfigurationError.invalidCPUCores(vm.cpuCores)
        }
        
        // Validate timeouts
        if vm.bootTimeout < 10 || vm.bootTimeout > 300 {
            throw ConfigurationError.invalidTimeout("boot", vm.bootTimeout)
        }
        
        if vm.shutdownTimeout < 5 || vm.shutdownTimeout > 120 {
            throw ConfigurationError.invalidTimeout("shutdown", vm.shutdownTimeout)
        }
    }
    
    /// Validate network configuration
    private func validateNetworkConfiguration(_ network: NetworkConfiguration) throws {
        // Validate network type
        let validTypes = ["user", "bridge", "tap"]
        if !validTypes.contains(network.type) {
            throw ConfigurationError.invalidNetworkType(network.type)
        }
        
        // Validate port forwards
        for forward in network.hostForwards {
            if forward.hostPort < 1024 || forward.hostPort > 65535 {
                throw ConfigurationError.invalidPort("host", forward.hostPort)
            }
            
            if forward.guestPort < 1 || forward.guestPort > 65535 {
                throw ConfigurationError.invalidPort("guest", forward.guestPort)
            }
            
            if !["tcp", "udp"].contains(forward.`protocol`) {
                throw ConfigurationError.invalidProtocol(forward.`protocol`)
            }
        }
    }
    
    /// Validate testing configuration
    private func validateTestingConfiguration(_ testing: TestingConfiguration) throws {
        // Validate test duration
        if testing.maxTestDuration < 30 || testing.maxTestDuration > 3600 {
            throw ConfigurationError.invalidTimeout("test", testing.maxTestDuration)
        }
        
        // Validate mock level
        let validMockLevels = ["high", "medium", "low", "none"]
        if !validMockLevels.contains(testing.mockLevel) {
            throw ConfigurationError.invalidMockLevel(testing.mockLevel)
        }
    }
    
    /// Generate QEMU command arguments from configuration
    public func generateQEMUArgs() throws -> [String] {
        let config = try loadConfiguration()
        var args: [String] = []
        
        // Memory
        args.append(contentsOf: ["-m", config.vm.memory])
        
        // CPU
        args.append(contentsOf: ["-smp", "\(config.vm.cpuCores)"])
        
        // KVM acceleration
        if config.vm.enableKVM {
            args.append("-enable-kvm")
        }
        
        // Network with port forwards
        var netdevArgs = "user,id=net0"
        for forward in config.network.hostForwards {
            netdevArgs += ",hostfwd=\(forward.`protocol`)::127.0.0.1:\(forward.hostPort)-:\(forward.guestPort)"
        }
        args.append(contentsOf: ["-netdev", netdevArgs])
        args.append(contentsOf: ["-device", "e1000,netdev=net0"])
        
        // Environment-specific arguments
        args.append(contentsOf: config.qemuArgs)
        
        logger.debug("Generated QEMU arguments", context: [
            "argCount": args.count,
            "args": args.joined(separator: " ")
        ])
        
        return args
    }
    
    /// Get test server configuration for current environment
    public func getTestServerConfiguration() throws -> TestServerConfiguration {
        let config = try loadConfiguration()
        let usbipPort = config.network.hostForwards.first { $0.description.contains("USB/IP") }?.hostPort ?? 3240
        
        return TestServerConfiguration(
            port: usbipPort,
            maxConnections: config.vm.cpuCores * 2,
            requestTimeout: getTimeouts().command,
            enableVerboseLogging: currentEnvironment == .development,
            mockLevel: config.testing.mockLevel,
            enableHardwareTests: config.testing.enableHardwareTests,
            enableSystemExtensionTests: config.testing.enableSystemExtensionTests,
            maxTestDuration: config.testing.maxTestDuration
        )
    }
}

/// Test server configuration derived from environment config
public struct TestServerConfiguration {
    public let port: Int
    public let maxConnections: Int
    public let requestTimeout: TimeInterval
    public let enableVerboseLogging: Bool
    public let mockLevel: String
    public let enableHardwareTests: Bool
    public let enableSystemExtensionTests: Bool
    public let maxTestDuration: TimeInterval
}

/// Configuration errors
public enum ConfigurationError: Error, LocalizedError {
    case invalidMemoryFormat(String)
    case invalidCPUCores(Int)
    case invalidTimeout(String, TimeInterval)
    case invalidNetworkType(String)
    case invalidPort(String, Int)
    case invalidProtocol(String)
    case invalidMockLevel(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidMemoryFormat(let format):
            return "Invalid memory format: \(format). Must end with M or G"
        case .invalidCPUCores(let cores):
            return "Invalid CPU cores: \(cores). Must be between 1 and 16"
        case .invalidTimeout(let type, let timeout):
            return "Invalid \(type) timeout: \(timeout)s"
        case .invalidNetworkType(let type):
            return "Invalid network type: \(type). Must be user, bridge, or tap"
        case .invalidPort(let type, let port):
            return "Invalid \(type) port: \(port)"
        case .invalidProtocol(let protocolName):
            return "Invalid protocol: \(protocolName). Must be tcp or udp"
        case .invalidMockLevel(let level):
            return "Invalid mock level: \(level). Must be high, medium, low, or none"
        }
    }
}