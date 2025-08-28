// CompletionExtractor.swift
// Extracts completion metadata from registered Command instances

import Foundation
import Common

/// Minimal interface for commands to extract completion data from
public protocol CompletableCommand {
    var name: String { get }
    var description: String { get }
}

/// Service that extracts completion data from CLI command structure
public class CompletionExtractor {
    
    /// Logger for completion extraction operations
    private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "completion-extractor")
    
    public init() {}
    
    /// Extract completion data from registered commands
    /// - Parameter commands: Array of registered CompletableCommand instances
    /// - Returns: Complete CompletionData structure for shell script generation
    public func extractCompletions(from commands: [CompletableCommand]) -> CompletionData {
        logger.debug("Starting completion extraction", context: ["commandCount": commands.count])
        
        let completionCommands = commands.compactMap { command in
            extractCommandMetadata(from: command)
        }.sorted { $0.name < $1.name }
        
        let globalOptions = extractGlobalOptions()
        let dynamicProviders = createDynamicValueProviders()
        let metadata = CompletionMetadata(version: "0.1.0")
        
        let completionData = CompletionData(
            commands: completionCommands,
            globalOptions: globalOptions,
            dynamicProviders: dynamicProviders,
            metadata: metadata
        )
        
        logger.info("Completion extraction completed", context: [
            "commandsExtracted": completionCommands.count,
            "globalOptions": globalOptions.count,
            "dynamicProviders": dynamicProviders.count
        ])
        
        return completionData
    }
    
    /// Extract completion metadata from a single command
    /// - Parameter command: The CompletableCommand instance to analyze
    /// - Returns: CompletionCommand with extracted metadata or nil if extraction fails
    public func extractCommandMetadata(from command: CompletableCommand) -> CompletionCommand? {
        logger.debug("Extracting metadata from command", context: ["commandName": command.name])
        
        let options = extractCommandOptions(from: command)
        let arguments = extractCommandArguments(from: command)
        let subcommands: [CompletionCommand] = [] // No subcommands in current CLI design
        
        let completionCommand = CompletionCommand(
            name: command.name,
            description: command.description,
            options: options,
            arguments: arguments,
            subcommands: subcommands
        )
        
        logger.debug("Command metadata extracted", context: [
            "commandName": command.name,
            "optionsCount": options.count,
            "argumentsCount": arguments.count
        ])
        
        return completionCommand
    }
    
    /// Extract command-line options from a command
    /// - Parameter command: The CompletableCommand instance to analyze
    /// - Returns: Array of CompletionOption instances
    public func extractCommandOptions(from command: CompletableCommand) -> [CompletionOption] {
        // Map known command options based on command name and existing help text patterns
        switch command.name {
        case "list":
            return [
                CompletionOption(
                    short: "l",
                    long: "local",
                    description: "Show local devices only (default)",
                    takesValue: false,
                    valueType: .none
                ),
                CompletionOption(
                    short: "r",
                    long: "remote",
                    description: "Show remote devices only",
                    takesValue: false,
                    valueType: .none
                ),
                CompletionOption(
                    short: "h",
                    long: "help",
                    description: "Show help message",
                    takesValue: false,
                    valueType: .none
                )
            ]
            
        case "bind", "unbind":
            return [
                CompletionOption(
                    short: "h",
                    long: "help",
                    description: "Show help message",
                    takesValue: false,
                    valueType: .none
                )
            ]
            
        case "attach":
            return [
                CompletionOption(
                    short: "h",
                    long: "help",
                    description: "Show help message",
                    takesValue: false,
                    valueType: .none
                )
            ]
            
        case "detach":
            return [
                CompletionOption(
                    short: "h",
                    long: "help",
                    description: "Show help message",
                    takesValue: false,
                    valueType: .none
                )
            ]
            
        case "daemon":
            return [
                CompletionOption(
                    short: "f",
                    long: "foreground",
                    description: "Run in foreground (do not daemonize)",
                    takesValue: false,
                    valueType: .none
                ),
                CompletionOption(
                    short: "c",
                    long: "config",
                    description: "Use alternative configuration file",
                    takesValue: true,
                    valueType: .file
                ),
                CompletionOption(
                    short: "h",
                    long: "help",
                    description: "Show help message",
                    takesValue: false,
                    valueType: .none
                )
            ]
            
        case "install-system-extension":
            return [
                CompletionOption(
                    short: "v",
                    long: "verbose",
                    description: "Show detailed installation information",
                    takesValue: false,
                    valueType: .none
                ),
                CompletionOption(
                    long: "skip-verification",
                    description: "Skip final installation verification",
                    takesValue: false,
                    valueType: .none
                ),
                CompletionOption(
                    short: "h",
                    long: "help",
                    description: "Show help message",
                    takesValue: false,
                    valueType: .none
                )
            ]
            
        case "diagnose":
            return [
                CompletionOption(
                    short: "v",
                    long: "verbose",
                    description: "Show detailed diagnostic information",
                    takesValue: false,
                    valueType: .none
                ),
                CompletionOption(
                    long: "bundle",
                    description: "Run only bundle detection diagnostics",
                    takesValue: false,
                    valueType: .none
                ),
                CompletionOption(
                    long: "installation",
                    description: "Run only installation status diagnostics",
                    takesValue: false,
                    valueType: .none
                ),
                CompletionOption(
                    long: "service",
                    description: "Run only service management diagnostics",
                    takesValue: false,
                    valueType: .none
                ),
                CompletionOption(
                    long: "all",
                    description: "Run all diagnostic modes (default)",
                    takesValue: false,
                    valueType: .none
                ),
                CompletionOption(
                    short: "h",
                    long: "help",
                    description: "Show help message",
                    takesValue: false,
                    valueType: .none
                )
            ]
            
        case "help":
            return [
                CompletionOption(
                    short: "h",
                    long: "help",
                    description: "Show help message",
                    takesValue: false,
                    valueType: .none
                )
            ]
            
        default:
            // For unknown commands, provide basic help option
            return [
                CompletionOption(
                    short: "h",
                    long: "help",
                    description: "Show help message",
                    takesValue: false,
                    valueType: .none
                )
            ]
        }
    }
    
    /// Extract command arguments from a command
    /// - Parameter command: The CompletableCommand instance to analyze
    /// - Returns: Array of CompletionArgument instances
    private func extractCommandArguments(from command: CompletableCommand) -> [CompletionArgument] {
        switch command.name {
        case "bind", "unbind":
            return [
                CompletionArgument(
                    name: "busid",
                    description: "The bus ID of the USB device (e.g., 1-1)",
                    required: true,
                    valueType: .busID
                )
            ]
            
        case "attach":
            return [
                CompletionArgument(
                    name: "host",
                    description: "The remote host running USB/IP server",
                    required: true,
                    valueType: .ipAddress
                ),
                CompletionArgument(
                    name: "busid",
                    description: "The bus ID of the USB device to attach",
                    required: true,
                    valueType: .busID
                )
            ]
            
        case "detach":
            return [
                CompletionArgument(
                    name: "port",
                    description: "The port number of the attached device",
                    required: true,
                    valueType: .port
                )
            ]
            
        case "help":
            return [
                CompletionArgument(
                    name: "command",
                    description: "Show help for specific command",
                    required: false,
                    valueType: .string
                )
            ]
            
        default:
            return []
        }
    }
    
    /// Extract global options that apply to all commands
    /// - Returns: Array of global CompletionOption instances
    private func extractGlobalOptions() -> [CompletionOption] {
        return [
            CompletionOption(
                short: "v",
                long: "version",
                description: "Show version information",
                takesValue: false,
                valueType: .none
            )
        ]
    }
    
    /// Create dynamic value providers for context-aware completion
    /// - Returns: Array of DynamicValueProvider instances
    private func createDynamicValueProviders() -> [DynamicValueProvider] {
        return [
            DynamicValueProvider(
                context: "device-id",
                command: "usbipd list | awk 'NR>1 {print $1}' | grep -E '^[0-9]+-[0-9]+' | head -10",
                fallback: ["1-1", "1-2", "2-1"]
            ),
            DynamicValueProvider(
                context: "bus-id",
                command: "usbipd list | awk 'NR>1 {print $1}' | grep -E '^[0-9]+-[0-9]+' | head -10",
                fallback: ["1-1", "1-2", "2-1"]
            ),
            DynamicValueProvider(
                context: "ip-address",
                command: "echo '192.168.1.100'; echo 'localhost'; echo '127.0.0.1'",
                fallback: ["192.168.1.100", "localhost", "127.0.0.1"]
            )
        ]
    }
}