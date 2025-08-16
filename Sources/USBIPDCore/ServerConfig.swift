// ServerConfig.swift
// Server configuration management for USB/IP server

import Foundation
import Common

/// Type alias for log level to use Common.LogLevel
public typealias LogLevel = Common.LogLevel

/// Extension to make Common.LogLevel Codable for configuration serialization
extension Common.LogLevel: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        
        switch rawValue.lowercased() {
        case "debug": self = .debug
        case "info": self = .info
        case "warning": self = .warning
        case "error": self = .error
        case "critical": self = .critical
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid log level: \(rawValue)"
                )
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let rawValue: String
        
        switch self {
        case .debug: rawValue = "debug"
        case .info: rawValue = "info"
        case .warning: rawValue = "warning"
        case .error: rawValue = "error"
        case .critical: rawValue = "critical"
        }
        
        try container.encode(rawValue)
    }
}

/// Extension to make DispatchQoS.QoSClass Codable for configuration serialization
extension DispatchQoS.QoSClass: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        
        switch rawValue.lowercased() {
        case "background": self = .background
        case "utility": self = .utility
        case "default": self = .default
        case "userinitiated": self = .userInitiated
        case "userinteractive": self = .userInteractive
        case "unspecified": self = .unspecified
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid QoS class: \(rawValue)"
                )
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let rawValue: String
        
        switch self {
        case .background: rawValue = "background"
        case .utility: rawValue = "utility"
        case .default: rawValue = "default"
        case .userInitiated: rawValue = "userinitiated"
        case .userInteractive: rawValue = "userinteractive"
        case .unspecified: rawValue = "unspecified"
        @unknown default: rawValue = "default"
        }
        
        try container.encode(rawValue)
    }
}

/// Server configuration class
public class ServerConfig: Codable {
    /// Default configuration file name
    public static let defaultConfigFileName = "usbipd-config.json"
    
    /// Default USB/IP port
    public static let defaultPort = 3240
    
    /// Default log level
    public static let defaultLogLevel = LogLevel.info
    
    /// Default configuration directory name
    public static let defaultConfigDirName = ".usbipd"
    
    /// Port to listen on
    public var port: Int
    
    /// Log level for server operations
    public var logLevel: LogLevel
    
    /// Enable debug mode for protocol-level details
    public var debugMode: Bool
    
    /// Maximum number of concurrent client connections
    public var maxConnections: Int
    
    /// Connection timeout in seconds
    public var connectionTimeout: TimeInterval
    
    /// Allowed device IDs (empty means all devices are allowed)
    public var allowedDevices: [String]
    
    /// Auto-bind devices on server start
    public var autoBindDevices: Bool
    
    /// Log file path (nil means log to stdout only)
    public var logFilePath: String?
    
    // MARK: - USB Operation Configuration
    
    /// Maximum concurrent USB requests per client connection
    public var maxConcurrentRequests: Int
    
    /// Maximum total concurrent requests across all clients
    public var maxTotalConcurrentRequests: Int
    
    /// Default timeout for USB operations in milliseconds
    public var usbOperationTimeout: UInt32
    
    /// Maximum buffer size for USB transfers (1MB default)
    public var maxUSBBufferSize: UInt32
    
    /// Maximum number of pending URBs per device
    public var maxPendingURBsPerDevice: Int
    
    /// USB request processing queue quality of service
    public var usbRequestQoS: DispatchQoS.QoSClass
    
    // MARK: - System Extension Configuration
    
    /// System Extension bundle configuration (optional)
    public var systemExtensionBundleConfig: SystemExtensionBundleConfig?
    
    /// Enable automatic System Extension installation
    public var enableSystemExtensionAutoInstall: Bool
    
    /// Maximum automatic installation attempts before giving up
    public var maxAutoInstallAttempts: Int
    
    /// Minimum time between automatic installation attempts (in seconds)
    public var autoInstallRetryDelay: TimeInterval
    
    /// Initialize with default values
    public init(
        port: Int = defaultPort,
        logLevel: LogLevel = defaultLogLevel,
        debugMode: Bool = false,
        maxConnections: Int = 10,
        connectionTimeout: TimeInterval = 30.0,
        allowedDevices: [String] = [],
        autoBindDevices: Bool = false,
        logFilePath: String? = nil,
        maxConcurrentRequests: Int = 16,
        maxTotalConcurrentRequests: Int = 64,
        usbOperationTimeout: UInt32 = 5000,
        maxUSBBufferSize: UInt32 = 1048576,
        maxPendingURBsPerDevice: Int = 32,
        usbRequestQoS: DispatchQoS.QoSClass = .userInitiated,
        systemExtensionBundleConfig: SystemExtensionBundleConfig? = nil,
        enableSystemExtensionAutoInstall: Bool = true,
        maxAutoInstallAttempts: Int = 3,
        autoInstallRetryDelay: TimeInterval = 30.0
    ) {
        self.port = port
        self.logLevel = logLevel
        self.debugMode = debugMode
        self.maxConnections = maxConnections
        self.connectionTimeout = connectionTimeout
        self.allowedDevices = allowedDevices
        self.autoBindDevices = autoBindDevices
        self.logFilePath = logFilePath
        self.maxConcurrentRequests = maxConcurrentRequests
        self.maxTotalConcurrentRequests = maxTotalConcurrentRequests
        self.usbOperationTimeout = usbOperationTimeout
        self.maxUSBBufferSize = maxUSBBufferSize
        self.maxPendingURBsPerDevice = maxPendingURBsPerDevice
        self.usbRequestQoS = usbRequestQoS
        self.systemExtensionBundleConfig = systemExtensionBundleConfig
        self.enableSystemExtensionAutoInstall = enableSystemExtensionAutoInstall
        self.maxAutoInstallAttempts = maxAutoInstallAttempts
        self.autoInstallRetryDelay = autoInstallRetryDelay
    }
    
    /// Load configuration from file
    /// - Parameter filePath: Path to configuration file (optional, uses default if nil)
    /// - Returns: ServerConfig instance loaded from file, or default config if file doesn't exist
    /// - Throws: Configuration loading errors
    public static func load(from filePath: String? = nil) throws -> ServerConfig {
        let configPath = filePath ?? defaultConfigPath()
        
        // Return default config if file doesn't exist
        guard FileManager.default.fileExists(atPath: configPath) else {
            return ServerConfig()
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            let decoder = JSONDecoder()
            let config = try decoder.decode(ServerConfig.self, from: data)
            
            // Validate the loaded configuration
            try config.validate()
            
            return config
        } catch let decodingError as DecodingError {
            throw ServerError.configurationError("Failed to decode configuration from \(configPath): \(decodingError.localizedDescription)")
        } catch let validationError as ServerError {
            throw validationError
        } catch {
            throw ServerError.configurationError("Failed to load configuration from \(configPath): \(error.localizedDescription)")
        }
    }
    
    /// Save configuration to file
    /// - Parameter filePath: Path to save configuration file (optional, uses default if nil)
    /// - Throws: Configuration saving errors
    public func save(to filePath: String? = nil) throws {
        // Validate before saving
        try validate()
        
        let configPath = filePath ?? ServerConfig.defaultConfigPath()
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            
            // Create directory if it doesn't exist
            let configURL = URL(fileURLWithPath: configPath)
            let configDir = configURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true, attributes: nil)
            
            try data.write(to: configURL, options: .atomic)
        } catch let encodingError as EncodingError {
            throw ServerError.configurationError("Failed to encode configuration for \(configPath): \(encodingError.localizedDescription)")
        } catch {
            throw ServerError.configurationError("Failed to save configuration to \(configPath): \(error.localizedDescription)")
        }
    }
    
    /// Get default configuration file path
    /// - Returns: Default path for configuration file
    public static func defaultConfigPath() -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent(defaultConfigDirName).appendingPathComponent(defaultConfigFileName).path
    }
    
    /// Get configuration directory path
    /// - Returns: Path to configuration directory
    public static func configDirectoryPath() -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent(defaultConfigDirName).path
    }
    
    /// Check if a log message should be logged based on current log level
    /// - Parameter messageLevel: Log level of the message
    /// - Returns: True if message should be logged
    public func shouldLog(level messageLevel: LogLevel) -> Bool {
        return messageLevel >= logLevel
    }
    
    /// Validate configuration values
    /// - Throws: Configuration validation errors
    public func validate() throws {
        guard port > 0 && port <= 65535 else {
            throw ServerError.configurationError("Invalid port number: \(port). Must be between 1 and 65535.")
        }
        
        guard maxConnections > 0 else {
            throw ServerError.configurationError("Invalid max connections: \(maxConnections). Must be greater than 0.")
        }
        
        guard connectionTimeout > 0 else {
            throw ServerError.configurationError("Invalid connection timeout: \(connectionTimeout). Must be greater than 0.")
        }
        
        // Validate USB operation parameters
        guard maxConcurrentRequests > 0 && maxConcurrentRequests <= 128 else {
            throw ServerError.configurationError("Invalid max concurrent requests: \(maxConcurrentRequests). Must be between 1 and 128.")
        }
        
        guard maxTotalConcurrentRequests > 0 && maxTotalConcurrentRequests >= maxConcurrentRequests else {
            throw ServerError.configurationError("Invalid max total concurrent requests: \(maxTotalConcurrentRequests). Must be >= maxConcurrentRequests.")
        }
        
        guard usbOperationTimeout > 0 && usbOperationTimeout <= 60000 else {
            throw ServerError.configurationError("Invalid USB operation timeout: \(usbOperationTimeout)ms. Must be between 1 and 60000ms.")
        }
        
        guard maxUSBBufferSize > 0 && maxUSBBufferSize <= 10485760 else { // 10MB limit
            throw ServerError.configurationError("Invalid max USB buffer size: \(maxUSBBufferSize) bytes. Must be between 1 and 10MB.")
        }
        
        guard maxPendingURBsPerDevice > 0 && maxPendingURBsPerDevice <= 256 else {
            throw ServerError.configurationError("Invalid max pending URBs per device: \(maxPendingURBsPerDevice). Must be between 1 and 256.")
        }
        
        // Validate System Extension configuration
        guard maxAutoInstallAttempts >= 0 && maxAutoInstallAttempts <= 10 else {
            throw ServerError.configurationError("Invalid max auto install attempts: \(maxAutoInstallAttempts). Must be between 0 and 10.")
        }
        
        guard autoInstallRetryDelay >= 0 && autoInstallRetryDelay <= 3600 else {
            throw ServerError.configurationError("Invalid auto install retry delay: \(autoInstallRetryDelay)s. Must be between 0 and 3600 seconds.")
        }
        
        // Validate log file path if specified
        if let logPath = logFilePath {
            let logFileURL = URL(fileURLWithPath: logPath)
            let logDir = logFileURL.deletingLastPathComponent()
            
            // Check if directory exists or can be created
            if !FileManager.default.fileExists(atPath: logDir.path) {
                do {
                    try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    throw ServerError.configurationError("Invalid log file path: \(logPath). Directory cannot be created: \(error.localizedDescription)")
                }
            }
            
            // Check if file is writable or can be created
            if FileManager.default.fileExists(atPath: logPath) {
                guard FileManager.default.isWritableFile(atPath: logPath) else {
                    throw ServerError.configurationError("Invalid log file path: \(logPath). File is not writable.")
                }
            } else {
                guard FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil) else {
                    throw ServerError.configurationError("Invalid log file path: \(logPath). File cannot be created.")
                }
                try FileManager.default.removeItem(atPath: logPath)
            }
        }
    }
    
    /// Reset configuration to default values
    public func resetToDefaults() {
        port = ServerConfig.defaultPort
        logLevel = ServerConfig.defaultLogLevel
        debugMode = false
        maxConnections = 10
        connectionTimeout = 30.0
        allowedDevices = []
        autoBindDevices = false
        logFilePath = nil
        maxConcurrentRequests = 16
        maxTotalConcurrentRequests = 64
        usbOperationTimeout = 5000
        maxUSBBufferSize = 1048576
        maxPendingURBsPerDevice = 32
        usbRequestQoS = .userInitiated
        systemExtensionBundleConfig = nil
        enableSystemExtensionAutoInstall = true
        maxAutoInstallAttempts = 3
        autoInstallRetryDelay = 30.0
    }
    
    /// Check if a device is allowed based on configuration
    /// - Parameter deviceID: Device ID to check
    /// - Returns: True if device is allowed
    public func isDeviceAllowed(_ deviceID: String) -> Bool {
        // If no allowed devices are specified, all devices are allowed
        guard !allowedDevices.isEmpty else {
            return true
        }
        
        return allowedDevices.contains(deviceID)
    }
    
    /// Add a device to the allowed devices list
    /// - Parameter deviceID: Device ID to add
    public func allowDevice(_ deviceID: String) {
        if !allowedDevices.contains(deviceID) {
            allowedDevices.append(deviceID)
        }
    }
    
    /// Remove a device from the allowed devices list
    /// - Parameter deviceID: Device ID to remove
    /// - Returns: True if device was removed, false if it wasn't in the list
    @discardableResult
    public func disallowDevice(_ deviceID: String) -> Bool {
        if let index = allowedDevices.firstIndex(of: deviceID) {
            allowedDevices.remove(at: index)
            return true
        }
        return false
    }
    
    // MARK: - System Extension Bundle Configuration
    
    /// Update the System Extension bundle configuration
    /// - Parameter bundleConfig: New bundle configuration
    public func updateSystemExtensionBundleConfig(_ bundleConfig: SystemExtensionBundleConfig?) {
        self.systemExtensionBundleConfig = bundleConfig
    }
    
    /// Check if System Extension auto-installation is enabled and configured
    /// - Returns: True if auto-installation should be attempted
    public func shouldAttemptAutoInstall() -> Bool {
        return enableSystemExtensionAutoInstall && maxAutoInstallAttempts > 0
    }
    
    /// Check if System Extension bundle is configured and valid
    /// - Returns: True if bundle is available for installation
    public func hasValidSystemExtensionBundle() -> Bool {
        guard let bundleConfig = systemExtensionBundleConfig else {
            return false
        }
        return bundleConfig.isValid
    }
    
    /// Get System Extension bundle path if available
    /// - Returns: Bundle path or nil if not configured
    public func getSystemExtensionBundlePath() -> String? {
        return systemExtensionBundleConfig?.bundlePath
    }
    
    /// Get System Extension bundle identifier if available
    /// - Returns: Bundle identifier or nil if not configured
    public func getSystemExtensionBundleIdentifier() -> String? {
        return systemExtensionBundleConfig?.bundleIdentifier
    }
}

// MARK: - System Extension Bundle Configuration Models
// Note: These types are referenced from SystemExtensionBundleDetector

/// System Extension installation status (imported from SystemExtensionModels.swift)
public typealias SystemExtensionInstallationStatus = USBIPDCore.SystemExtensionInstallationStatus

/// Bundle configuration structure (mirrors SystemExtensionBundleDetector.SystemExtensionBundleConfig)
/// This is defined here to avoid circular imports between ServerConfig and BundleDetector
public struct SystemExtensionBundleConfig: Codable {
    /// Path to the System Extension bundle
    public let bundlePath: String
    
    /// Bundle identifier
    public let bundleIdentifier: String
    
    /// Last detection timestamp
    public let lastDetectionTime: Date
    
    /// Bundle validation status
    public let isValid: Bool
    
    /// Installation status of this bundle
    public let installationStatus: SystemExtensionInstallationStatus
    
    /// Issues found during detection/validation
    public let detectionIssues: [String]
    
    /// Bundle size in bytes (for monitoring changes)
    public let bundleSize: Int64
    
    /// Bundle modification time (for change detection)
    public let modificationTime: Date
    
    public init(
        bundlePath: String,
        bundleIdentifier: String,
        lastDetectionTime: Date = Date(),
        isValid: Bool,
        installationStatus: SystemExtensionInstallationStatus = .unknown,
        detectionIssues: [String] = [],
        bundleSize: Int64 = 0,
        modificationTime: Date = Date()
    ) {
        self.bundlePath = bundlePath
        self.bundleIdentifier = bundleIdentifier
        self.lastDetectionTime = lastDetectionTime
        self.isValid = isValid
        self.installationStatus = installationStatus
        self.detectionIssues = detectionIssues
        self.bundleSize = bundleSize
        self.modificationTime = modificationTime
    }
}

/// Extension to add configuration error to ServerError
extension ServerError {
    public static func configurationError(_ message: String) -> ServerError {
        return .initializationFailed("Configuration error: \(message)")
    }
}