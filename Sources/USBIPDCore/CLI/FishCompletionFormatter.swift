// FishCompletionFormatter.swift
// Fish-specific completion script formatter with intelligent context-aware suggestions

import Foundation

/// Fish completion formatter that generates fish-compatible completion scripts with intelligent suggestions
public class FishCompletionFormatter: ShellCompletionFormatter {
    
    public let shellType = "fish"
    public let fileExtension = "fish"
    
    public init() {}
    
    /// Format completion data into a fish completion script
    /// - Parameter data: The completion data to format
    /// - Returns: Complete fish completion script
    public func formatCompletion(data: CompletionData) -> String {
        let header = CompletionFormattingUtilities.generateHeader(shellType: shellType, metadata: data.metadata)
        let completionCommands = generateCompletionCommands(data: data)
        let helperFunctions = generateHelperFunctions()
        
        return """
        \(header)
        \(completionCommands)
        
        \(helperFunctions)
        """
    }
    
    /// Format a command with its options and arguments for fish completion
    /// - Parameters:
    ///   - command: The command to format
    ///   - depth: Nesting depth (not used in fish, kept for protocol compliance)
    /// - Returns: Fish completion statements for the command
    public func formatCommand(_ command: CompletionCommand, depth: Int = 0) -> String {
        var completionLines: [String] = []
        
        // Command completion when no subcommand is used
        let escapedDescription = CompletionFormattingUtilities.escapeForShell(command.description, shellType: shellType)
        completionLines.append("complete -c usbipd -n '__fish_use_subcommand' -a '\(command.name)' -d '\(escapedDescription)'")
        
        // Options completion for this command
        for option in command.options {
            let optionCompletion = formatCommandOption(option, for: command.name)
            completionLines.append(optionCompletion)
        }
        
        // Arguments completion for this command
        for (index, argument) in command.arguments.enumerated() {
            let argumentCompletion = formatCommandArgument(argument, for: command.name, position: index + 1)
            completionLines.append(argumentCompletion)
        }
        
        return completionLines.joined(separator: "\n")
    }
    
    /// Format command options for fish completion
    /// - Parameter options: Array of options to format
    /// - Returns: Fish complete statements for options
    public func formatOptions(_ options: [CompletionOption]) -> String {
        return options.map { option in
            formatGlobalOption(option)
        }.joined(separator: "\n")
    }
    
    /// Format dynamic value completion for fish
    /// - Parameter provider: Dynamic value provider
    /// - Returns: Fish function for dynamic completion
    public func formatDynamicCompletion(_ provider: DynamicValueProvider) -> String {
        let functionName = "__fish_usbipd_\(provider.context.replacingOccurrences(of: "-", with: "_"))"
        let escapedCommand = CompletionFormattingUtilities.escapeForShell(provider.command, shellType: shellType)
        let fallbackValues = provider.fallback.map { "'\($0)'" }.joined(separator: " ")
        
        return """
        # Dynamic completion function for \(provider.context)
        function \(functionName)
            if command -v usbipd >/dev/null 2>&1
                \(escapedCommand) 2>/dev/null; or echo \(fallbackValues)
            else
                echo \(fallbackValues)
            end
        end
        """
    }
    
    // MARK: - Private Implementation
    
    /// Generate all completion commands for fish
    /// - Parameter data: Completion data
    /// - Returns: All fish completion statements
    private func generateCompletionCommands(data: CompletionData) -> String {
        var completionLines: [String] = []
        
        // Global options
        for option in data.globalOptions {
            completionLines.append(formatGlobalOption(option))
        }
        
        // Commands and their specific completions
        for command in data.commands {
            let commandCompletions = formatCommand(command)
            completionLines.append(commandCompletions)
        }
        
        return completionLines.joined(separator: "\n\n")
    }
    
    /// Format a global option for fish completion
    /// - Parameter option: The global option to format
    /// - Returns: Fish complete statement for global option
    private func formatGlobalOption(_ option: CompletionOption) -> String {
        let escapedDescription = CompletionFormattingUtilities.escapeForShell(option.description, shellType: shellType)
        var completeParts: [String] = ["complete -c usbipd"]
        
        // Add short and long options
        if let short = option.short {
            completeParts.append("-s \(short)")
        }
        completeParts.append("-l \(option.long)")
        
        // Add description
        completeParts.append("-d '\(escapedDescription)'")
        
        // Add value completion if needed
        if option.takesValue {
            let valueCompletion = generateValueCompletion(for: option.valueType)
            if !valueCompletion.isEmpty {
                completeParts.append(valueCompletion)
            }
        }
        
        return completeParts.joined(separator: " ")
    }
    
    /// Format a command-specific option for fish completion
    /// - Parameters:
    ///   - option: The option to format
    ///   - commandName: The command this option belongs to
    /// - Returns: Fish complete statement for command option
    private func formatCommandOption(_ option: CompletionOption, for commandName: String) -> String {
        let escapedDescription = CompletionFormattingUtilities.escapeForShell(option.description, shellType: shellType)
        var completeParts: [String] = ["complete -c usbipd"]
        
        // Condition: only when this specific command is used
        completeParts.append("-n '__fish_seen_subcommand_from \(commandName)'")
        
        // Add short and long options
        if let short = option.short {
            completeParts.append("-s \(short)")
        }
        completeParts.append("-l \(option.long)")
        
        // Add description
        completeParts.append("-d '\(escapedDescription)'")
        
        // Add value completion if needed
        if option.takesValue {
            let valueCompletion = generateValueCompletion(for: option.valueType)
            if !valueCompletion.isEmpty {
                completeParts.append(valueCompletion)
            }
        }
        
        return completeParts.joined(separator: " ")
    }
    
    /// Format a command argument for fish completion
    /// - Parameters:
    ///   - argument: The argument to format
    ///   - commandName: The command this argument belongs to
    ///   - position: Argument position (1-based)
    /// - Returns: Fish complete statement for command argument
    private func formatCommandArgument(_ argument: CompletionArgument, for commandName: String, position: Int) -> String {
        var completeParts: [String] = ["complete -c usbipd"]
        
        // Condition: command and argument position
        completeParts.append("-n '__fish_seen_subcommand_from \(commandName); and __fish_is_nth_token \(position + 1)'")
        
        // Add value completion based on argument type
        let valueCompletion = generateValueCompletion(for: argument.valueType, commandName: commandName)
        if !valueCompletion.isEmpty {
            completeParts.append(valueCompletion)
        }
        
        return completeParts.joined(separator: " ")
    }
    
    /// Generate value completion specification for different value types
    /// - Parameters:
    ///   - valueType: The value type
    ///   - commandName: Optional command name for context
    /// - Returns: Fish completion specification
    private func generateValueCompletion(for valueType: CompletionValueType, commandName: String? = nil) -> String {
        switch valueType {
        case .file:
            return "-F"
            
        case .directory:
            return "-x -a '(__fish_complete_directories)'"
            
        case .deviceID, .busID:
            return "-x -a '(__fish_usbipd_device_ids)'"
            
        case .ipAddress:
            return "-x -a '(__fish_usbipd_ip_addresses)'"
            
        case .port:
            return "-x -a '(__fish_usbipd_ports)'"
            
        case .string:
            if commandName == "help" {
                return "-x -a '(__fish_usbipd_commands)'"
            }
            return ""
            
        case .none:
            return ""
        }
    }
    
    /// Generate helper functions for dynamic completion
    /// - Returns: Fish helper functions
    private func generateHelperFunctions() -> String {
        return """
        # Helper function to check if we're in a position to complete a subcommand
        function __fish_use_subcommand
            not __fish_seen_subcommand_from help list bind unbind attach detach daemon install-system-extension diagnose
        end
        
        # Helper function to check if we're at the nth token position
        function __fish_is_nth_token
            set -l cmd (commandline -opc)
            test (count $cmd) -eq $argv[1]
        end
        
        # Helper function to get available commands for help completion
        function __fish_usbipd_commands
            echo help
            echo list
            echo bind
            echo unbind
            echo attach
            echo detach
            echo daemon
            echo install-system-extension
            echo diagnose
        end
        
        # Helper function to get device IDs
        function __fish_usbipd_device_ids
            if command -v usbipd >/dev/null 2>&1
                usbipd list | awk 'NR>1 {print $1}' | grep -E '^[0-9]+-[0-9]+' | head -10 2>/dev/null
                or echo -e "1-1\\n1-2\\n2-1"
            else
                echo -e "1-1\\n1-2\\n2-1"
            end
        end
        
        # Helper function to get IP addresses with descriptions
        function __fish_usbipd_ip_addresses
            echo -e "localhost\\tLocal machine"
            echo -e "127.0.0.1\\tLocal loopback"
            echo -e "192.168.1.100\\tCommon LAN address"
            echo -e "192.168.1.1\\tCommon gateway address"
            echo -e "10.0.0.1\\tCommon private network"
        end
        
        # Helper function to get port numbers with descriptions
        function __fish_usbipd_ports
            echo -e "3240\\tDefault USB/IP port"
            echo -e "3241\\tAlternative USB/IP port"
            echo -e "3242\\tAlternative USB/IP port"
            echo -e "8080\\tCommon HTTP proxy port"
            echo -e "8000\\tDevelopment server port"
            echo -e "5000\\tCommon application port"
        end
        
        # Helper function to complete file paths (alternative to -F for more control)
        function __fish_usbipd_files
            __fish_complete_path
        end
        
        # Helper function to check if a specific command has been seen
        function __fish_seen_usbipd_command
            __fish_seen_subcommand_from $argv[1]
        end
        
        # Helper function for contextual completion based on previous arguments
        function __fish_usbipd_context_completion
            set -l cmd (commandline -opc)
            set -l current_command ""
            
            # Find the current command
            for token in $cmd[2..-1]
                if not string match -q -- "-*" $token
                    set current_command $token
                    break
                end
            end
            
            # Provide context-specific completion
            switch $current_command
                case bind unbind
                    __fish_usbipd_device_ids
                case attach
                    if test (count $cmd) -eq 3
                        __fish_usbipd_ip_addresses
                    else if test (count $cmd) -eq 4
                        __fish_usbipd_device_ids
                    end
                case detach
                    __fish_usbipd_ports
            end
        end
        """
    }
}