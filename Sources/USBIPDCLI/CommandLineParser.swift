// CommandLineParser.swift
// Command-line argument parser for USB/IP daemon

import Foundation
import USBIPDCore
import Common

// Logger for command-line operations
private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "cli-parser")

/// Represents a command that can be executed by the CLI
public protocol Command {
    /// The name of the command
    var name: String { get }
    
    /// Description of the command for help text
    var description: String { get }
    
    /// Execute the command with the given arguments
    func execute(with arguments: [String]) throws
}

/// Error types specific to command-line parsing and execution
public enum CommandLineError: Error, LocalizedError {
    case unknownCommand(String)
    case invalidArguments(String)
    case missingArguments(String)
    case executionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .unknownCommand(let cmd):
            return "Unknown command: \(cmd)"
        case .invalidArguments(let msg):
            return "Invalid arguments: \(msg)"
        case .missingArguments(let msg):
            return "Missing required arguments: \(msg)"
        case .executionFailed(let msg):
            return "Command execution failed: \(msg)"
        }
    }
}

/// Parser for command-line arguments
public class CommandLineParser {
    /// Dictionary of available commands
    private var commands: [String: Command] = [:]
    
    /// Device discovery instance
    private let deviceDiscovery: DeviceDiscovery
    
    /// Server configuration
    private let serverConfig: ServerConfig
    
    /// Server instance
    private let server: USBIPServer
    
    /// System Extension manager for device claiming operations
    private let systemExtensionManager: SystemExtensionManager?
    
    /// Initialize a new command-line parser with dependencies
    public init(deviceDiscovery: DeviceDiscovery, serverConfig: ServerConfig, server: USBIPServer, systemExtensionManager: SystemExtensionManager? = nil) {
        self.deviceDiscovery = deviceDiscovery
        self.serverConfig = serverConfig
        self.server = server
        self.systemExtensionManager = systemExtensionManager
        registerCommands()
    }
    
    /// Register all available commands
    private func registerCommands() {
        let outputFormatter = LinuxCompatibleOutputFormatter()
        
        let commands: [Command] = [
            HelpCommand(parser: self),
            ListCommand(deviceDiscovery: deviceDiscovery, outputFormatter: outputFormatter),
            BindCommand(deviceDiscovery: deviceDiscovery, serverConfig: serverConfig, systemExtensionManager: systemExtensionManager),
            UnbindCommand(deviceDiscovery: deviceDiscovery, serverConfig: serverConfig, systemExtensionManager: systemExtensionManager),
            StatusCommand(deviceClaimManager: nil, outputFormatter: outputFormatter),
            AttachCommand(),
            DetachCommand(),
            DaemonCommand(server: server, serverConfig: serverConfig),
            InstallSystemExtensionCommand(),
            DiagnoseCommand()
        ]
        
        for command in commands {
            self.commands[command.name] = command
        }
    }
    
    /// Parse and execute the given command-line arguments
    public func parse(arguments: [String]) throws {
        // Skip the first argument (program name)
        let args = Array(arguments.dropFirst())
        
        logger.debug("Parsing command-line arguments", context: ["arguments": args.joined(separator: " ")])
        
        if args.isEmpty {
            // Show help if no arguments provided
            logger.info("No command specified, showing help")
            try commands["help"]?.execute(with: [])
            return
        }
        
        let commandName = args[0]
        let commandArgs = Array(args.dropFirst())
        
        // Handle special flags that aren't commands
        if commandName == "--version" || commandName == "-v" {
            printVersion()
            return
        }
        
        logger.info("Executing command", context: ["command": commandName, "arguments": commandArgs.joined(separator: " ")])
        
        guard let command = commands[commandName] else {
            logger.error("Unknown command", context: ["command": commandName])
            throw CommandLineError.unknownCommand(commandName)
        }
        
        logger.debug("Found command handler", context: ["command": commandName, "type": String(describing: type(of: command))])
        
        try command.execute(with: commandArgs)
        logger.info("Command executed successfully", context: ["command": commandName])
    }
    
    /// Get all registered commands
    public func getCommands() -> [Command] {
        return Array(commands.values)
    }
    
    /// Print version information
    private func printVersion() {
        print("USB/IP Daemon for macOS")
        print("Version: 0.1.0")
        print("Build: \(getBuildInfo())")
        logger.info("Version information displayed")
    }
    
    /// Get build information
    private func getBuildInfo() -> String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }
}