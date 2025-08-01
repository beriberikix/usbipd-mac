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
        guard level >= config.level else { return }
        
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

// MARK: - Global Convenience Functions

/// Global debug logging function
public func logDebug(
    _ message: String,
    context: [String: Any] = [:],
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Logger.shared.debug(message, context: context, file: file, function: function, line: line)
}

/// Global info logging function
public func logInfo(
    _ message: String,
    context: [String: Any] = [:],
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Logger.shared.info(message, context: context, file: file, function: function, line: line)
}

/// Global warning logging function
public func logWarning(
    _ message: String,
    context: [String: Any] = [:],
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Logger.shared.warning(message, context: context, file: file, function: function, line: line)
}

/// Global error logging function
public func logError(
    _ message: String,
    context: [String: Any] = [:],
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Logger.shared.error(message, context: context, file: file, function: function, line: line)
}

/// Global critical logging function
public func logCritical(
    _ message: String,
    context: [String: Any] = [:],
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Logger.shared.critical(message, context: context, file: file, function: function, line: line)
}

/// Global error logging function for Error objects
public func logError(
    _ error: Error,
    message: String? = nil,
    context: [String: Any] = [:],
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    Logger.shared.error(error, message: message, context: context, file: file, function: function, line: line)
}