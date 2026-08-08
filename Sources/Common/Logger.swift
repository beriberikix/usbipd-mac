import Foundation
import os.log

/// Log levels supported by the Logger
public enum LogLevel: Int, CaseIterable, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case critical = 4
    
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
    
    /// String representation of the log level
    public var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .critical: return "CRITICAL"
        }
    }
}

/// Codable conformance for LogLevel.
///
/// Declared here, in the module that owns the type, rather than retroactively from
/// USBIPDCore. Conforming an imported type to an imported protocol is a warning on
/// current Swift compilers, and the CI test build promotes it to an error via
/// -Xswiftc -warnings-as-errors.
///
/// Encodes as a lowercase string rather than the Int raw value, preserving the
/// on-disk config format written by earlier versions. Do not replace this with
/// synthesized conformance: that would silently switch the format to integers and
/// break existing config files.
extension LogLevel: Codable {
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

private extension LogLevel {
    /// OSLogType mapping for system logging
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
}

/// Logger configuration
public struct LoggerConfig {
    /// Minimum log level to output
    public let level: LogLevel
    
    /// Whether to include timestamps in log output
    public let includeTimestamp: Bool
    
    /// Whether to include the source context (file, function, line)
    public let includeContext: Bool
    
    /// Date formatter for timestamps
    public let dateFormatter: DateFormatter
    
    public init(
        level: LogLevel = .info,
        includeTimestamp: Bool = true,
        includeContext: Bool = false
    ) {
        self.level = level
        self.includeTimestamp = includeTimestamp
        self.includeContext = includeContext
        
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }
}

/// Thread-safe logger implementation for USB/IP server
public final class Logger {
    private let config: LoggerConfig
    private let osLog: OSLog
    private let queue = DispatchQueue(label: "com.usbipd.logger", qos: .utility)
    
    /// Shared logger instance
    public static let shared = Logger()

    /// Process-wide floor on what gets emitted.
    ///
    /// Every component constructs its own `Logger` with a hardcoded level — 27 at
    /// `.info` and 3 at `.debug` — so `ServerConfig.logLevel` controlled nothing and a
    /// plain `usbipd list` printed dozens of DEBUG lines around its output. Rather than
    /// chase every call site, the stricter of the two levels wins, so this single value
    /// governs verbosity.
    ///
    /// Defaults to `.warning`: a CLI should print its results, not its reasoning. The
    /// daemon raises it, since its output goes to a log file where detail is wanted.
    /// `USBIPD_LOG_LEVEL=debug|info|warning|error|critical` overrides it.
    public static var globalLevel: LogLevel = {
        if let raw = ProcessInfo.processInfo.environment["USBIPD_LOG_LEVEL"]?.lowercased() {
            switch raw {
            case "debug": return .debug
            case "info": return .info
            case "warning", "warn": return .warning
            case "error": return .error
            case "critical": return .critical
            default: break
            }
        }
        return .warning
    }()
    
    /// Initialize logger with configuration
    /// - Parameters:
    ///   - config: Logger configuration
    ///   - subsystem: OSLog subsystem identifier
    ///   - category: OSLog category
    public init(
        config: LoggerConfig = LoggerConfig(),
        subsystem: String = "com.usbipd.mac",
        category: String = "default"
    ) {
        self.config = config
        self.osLog = OSLog(subsystem: subsystem, category: category)
    }
    
    /// Log a message at the specified level
    /// - Parameters:
    ///   - level: Log level
    ///   - message: Message to log
    ///   - context: Additional context information
    ///   - file: Source file (automatically filled)
    ///   - function: Source function (automatically filled)
    ///   - line: Source line (automatically filled)
    public func log(
        _ level: LogLevel,
        _ message: String,
        context: [String: Any] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        // Check if we should log at this level
        // The stricter of the instance level and the process-wide floor.
        guard level >= config.level, level >= Logger.globalLevel else { return }
        
        queue.async { [weak self] in
            self?.performLog(level, message, context: context, file: file, function: function, line: line)
        }
    }
    
    /// Convenience method for debug logging
    public func debug(
        _ message: String,
        context: [String: Any] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.debug, message, context: context, file: file, function: function, line: line)
    }
    
    /// Convenience method for info logging
    public func info(
        _ message: String,
        context: [String: Any] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.info, message, context: context, file: file, function: function, line: line)
    }
    
    /// Convenience method for warning logging
    public func warning(
        _ message: String,
        context: [String: Any] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.warning, message, context: context, file: file, function: function, line: line)
    }
    
    /// Convenience method for error logging
    public func error(
        _ message: String,
        context: [String: Any] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.error, message, context: context, file: file, function: function, line: line)
    }
    
    /// Convenience method for critical logging
    public func critical(
        _ message: String,
        context: [String: Any] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.critical, message, context: context, file: file, function: function, line: line)
    }
    
    /// Log an error with additional error context
    public func error(
        _ error: Error,
        message: String? = nil,
        context: [String: Any] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        var fullContext = context
        fullContext["error"] = String(describing: error)
        
        let errorMessage = message ?? "Error occurred: \(error.localizedDescription)"
        log(.error, errorMessage, context: fullContext, file: file, function: function, line: line)
    }
    
    // MARK: - Private Methods
    
    private func performLog(
        _ level: LogLevel,
        _ message: String,
        context: [String: Any],
        file: String,
        function: String,
        line: Int
    ) {
        let formattedMessage = formatMessage(level, message, context: context, file: file, function: function, line: line)
        
        // Log to system log
        os_log("%{public}@", log: osLog, type: level.osLogType, formattedMessage)
        
        // Also log to stderr for CLI visibility
        fputs(formattedMessage + "\n", stderr)
    }
    
    private func formatMessage(
        _ level: LogLevel,
        _ message: String,
        context: [String: Any],
        file: String,
        function: String,
        line: Int
    ) -> String {
        var components: [String] = []
        
        // Add timestamp if configured
        if config.includeTimestamp {
            components.append(config.dateFormatter.string(from: Date()))
        }
        
        // Add log level
        components.append("[\(level.description)]")
        
        // Add context if configured
        if config.includeContext {
            let filename = URL(fileURLWithPath: file).lastPathComponent
            components.append("[\(filename):\(line) \(function)]")
        }
        
        // Add the main message
        components.append(message)
        
        // Add context information if provided
        if !context.isEmpty {
            let contextString = context.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            components.append("{\(contextString)}")
        }
        
        return components.joined(separator: " ")
    }
}
