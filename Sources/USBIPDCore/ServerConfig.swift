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
    
    /// Initialize with default values
    public init(
        port: Int = defaultPort,
        logLevel: LogLevel = defaultLogLevel,
        debugMode: Bool = false,
        maxConnections: Int = 10,
        connectionTimeout: TimeInterval = 30.0,
        allowedDevices: [String] = [],
        autoBindDevices: Bool = false,
        logFilePath: String? = nil
    ) {
        self.port = port
        self.logLevel = logLevel
        self.debugMode = debugMode
        self.maxConnections = maxConnections
        self.connectionTimeout = connectionTimeout
        self.allowedDevices = allowedDevices
        self.autoBindDevices = autoBindDevices
        self.logFilePath = logFilePath
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
}

/// Extension to add configuration error to ServerError
extension ServerError {
    public static func configurationError(_ message: String) -> ServerError {
        return .initializationFailed("Configuration error: \(message)")
    }
}