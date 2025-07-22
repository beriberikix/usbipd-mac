// CommandLineParser.swift
// Command-line argument parser for USB/IP daemon

import Foundation
import USBIPDCore
import Common

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
    
    /// Initialize a new command-line parser with dependencies
    public init(deviceDiscovery: DeviceDiscovery, serverConfig: ServerConfig, server: USBIPServer) {
        self.deviceDiscovery = deviceDiscovery
        self.serverConfig = serverConfig
        self.server = server
        registerCommands()
    }
    
    /// Initialize a new command-line parser with default dependencies
    public convenience init() {
        // Create default dependencies
        let deviceDiscovery = IOKitDeviceDiscovery()
        
        // Load or create default server config
        let serverConfig: ServerConfig
        do {
            serverConfig = try ServerConfig.load()
        } catch {
            print("Warning: Failed to load server configuration: \(error.localizedDescription)")
            print("Using default configuration.")
            serverConfig = ServerConfig()
        }
        
        // Create network service
        let networkService = TCPServer()
        
        // Create server
        let server = ServerCoordinator(
            networkService: networkService,
            deviceDiscovery: deviceDiscovery,
            config: serverConfig
        )
        
        self.init(deviceDiscovery: deviceDiscovery, serverConfig: serverConfig, server: server)
    }
    
    /// Register all available commands
    private func registerCommands() {
        let outputFormatter = LinuxCompatibleOutputFormatter()
        
        let commands: [Command] = [
            HelpCommand(parser: self),
            ListCommand(deviceDiscovery: deviceDiscovery, outputFormatter: outputFormatter),
            BindCommand(deviceDiscovery: deviceDiscovery, serverConfig: serverConfig),
            UnbindCommand(deviceDiscovery: deviceDiscovery, serverConfig: serverConfig),
            AttachCommand(),
            DetachCommand(),
            DaemonCommand(server: server, serverConfig: serverConfig)
        ]
        
        for command in commands {
            self.commands[command.name] = command
        }
    }
    
    /// Parse and execute the given command-line arguments
    public func parse(arguments: [String]) throws {
        // Skip the first argument (program name)
        let args = Array(arguments.dropFirst())
        
        if args.isEmpty {
            // Show help if no arguments provided
            try commands["help"]?.execute(with: [])
            return
        }
        
        let commandName = args[0]
        let commandArgs = Array(args.dropFirst())
        
        guard let command = commands[commandName] else {
            throw CommandLineError.unknownCommand(commandName)
        }
        
        try command.execute(with: commandArgs)
    }
    
    /// Get all registered commands
    public func getCommands() -> [Command] {
        return Array(commands.values)
    }
}