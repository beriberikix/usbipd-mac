// ZshCompletionFormatter.swift
// Zsh-specific completion script formatter with enhanced descriptions

import Foundation

/// Zsh completion formatter that generates zsh-compatible completion scripts with rich descriptions
public class ZshCompletionFormatter: ShellCompletionFormatter {
    
    public let shellType = "zsh"
    public let fileExtension = ""
    
    public init() {}
    
    /// Format completion data into a zsh completion script
    /// - Parameter data: The completion data to format
    /// - Returns: Complete zsh completion script with #compdef header
    public func formatCompletion(data: CompletionData) -> String {
        let header = CompletionFormattingUtilities.generateHeader(shellType: shellType, metadata: data.metadata)
        let compdefHeader = "#compdef usbipd"
        let completionFunction = generateCompletionFunction(data: data)
        let functionCall = generateFunctionCall()
        
        return """
        \(compdefHeader)
        \(header)
        \(completionFunction)
        
        \(functionCall)
        """
    }
    
    /// Format a command with its options and arguments for zsh completion
    /// - Parameters:
    ///   - command: The command to format
    ///   - depth: Nesting depth (not used in current zsh design, kept for protocol compliance)
    /// - Returns: Zsh completion case statement for the command
    public func formatCommand(_ command: CompletionCommand, depth: Int = 0) -> String {
        let optionsArray = generateOptionsArray(command.options)
        let argumentHandling = generateArgumentHandling(for: command)
        
        return """
            \(command.name))
                _arguments -C \\
        \(optionsArray)\(argumentHandling.isEmpty ? "" : " \\\\\n\(argumentHandling)")
                ;;
        """
    }
    
    /// Format command options for zsh completion with descriptions
    /// - Parameter options: Array of options to format
    /// - Returns: Zsh _arguments style option specifications
    public func formatOptions(_ options: [CompletionOption]) -> String {
        return options.map { option in
            formatSingleOption(option)
        }.joined(separator: " \\\\\n")
    }
    
    /// Format dynamic value completion for zsh
    /// - Parameter provider: Dynamic value provider
    /// - Returns: Zsh completion specification for dynamic values
    public func formatDynamicCompletion(_ provider: DynamicValueProvider) -> String {
        let escapedCommand = CompletionFormattingUtilities.escapeForShell(provider.command, shellType: shellType)
        let fallbackValues = provider.fallback.map { "'\($0)'" }.joined(separator: " ")
        
        return """
        # Dynamic completion for \(provider.context)
        local \(provider.context.replacingOccurrences(of: "-", with: "_"))_values
        if (( $+commands[usbipd] )); then
            \(provider.context.replacingOccurrences(of: "-", with: "_"))_values=($(\(escapedCommand) 2>/dev/null || echo \(fallbackValues)))
        else
            \(provider.context.replacingOccurrences(of: "-", with: "_"))_values=(\(fallbackValues))
        fi
        _describe '\(provider.context)' \(provider.context.replacingOccurrences(of: "-", with: "_"))_values
        """
    }
    
    // MARK: - Private Implementation
    
    /// Generate the main zsh completion function
    /// - Parameter data: Completion data
    /// - Returns: Complete zsh completion function
    private func generateCompletionFunction(data: CompletionData) -> String {
        let commandDescriptions = generateCommandDescriptions(data.commands)
        let commandCases = generateCommandCases(data: data)
        let globalOptionsArray = generateGlobalOptionsArray(data.globalOptions)
        
        return """
        # Main zsh completion function for usbipd
        _usbipd() {
            local context state state_descr line
            typeset -A opt_args
            
            _arguments -C \\
        \(globalOptionsArray) \\
                '1: :_usbipd_commands' \\
                '*:: :->command_args'
            
            case $state in
                command_args)
                    case $line[1] in
        \(commandCases)
                    esac
                    ;;
            esac
        }
        
        # Command completion function
        _usbipd_commands() {
            local commands=(
        \(commandDescriptions)
            )
            _describe 'commands' commands
        }
        """
    }
    
    /// Generate command descriptions for zsh _describe
    /// - Parameter commands: Array of commands
    /// - Returns: Formatted command descriptions
    private func generateCommandDescriptions(_ commands: [CompletionCommand]) -> String {
        return commands.map { command in
            let escapedDescription = CompletionFormattingUtilities.escapeForShell(command.description, shellType: shellType)
            return "        '\(command.name):\(escapedDescription)'"
        }.joined(separator: "\n")
    }
    
    /// Generate case statements for all commands
    /// - Parameter data: Completion data
    /// - Returns: All command case statements
    private func generateCommandCases(data: CompletionData) -> String {
        return data.commands.map { command in
            formatCommand(command)
        }.joined(separator: "\n")
    }
    
    /// Generate global options array for zsh
    /// - Parameter options: Global options
    /// - Returns: Formatted global options for _arguments
    private func generateGlobalOptionsArray(_ options: [CompletionOption]) -> String {
        if options.isEmpty {
            return ""
        }
        
        return options.map { option in
            formatSingleOption(option)
        }.joined(separator: " \\\\\n") + " \\\\"
    }
    
    /// Generate options array for a specific command
    /// - Parameter options: Command options
    /// - Returns: Formatted options for _arguments
    private func generateOptionsArray(_ options: [CompletionOption]) -> String {
        if options.isEmpty {
            return ""
        }
        
        return options.map { option in
            "                    " + formatSingleOption(option)
        }.joined(separator: " \\\\\n")
    }
    
    /// Format a single option for zsh completion
    /// - Parameter option: The option to format
    /// - Returns: Zsh _arguments style option specification
    private func formatSingleOption(_ option: CompletionOption) -> String {
        let escapedDescription = CompletionFormattingUtilities.escapeForShell(option.description, shellType: shellType)
        
        if let short = option.short {
            if option.takesValue {
                let valueSpec = generateValueSpec(for: option.valueType)
                return "'{-\(short),--\(option.long)}[\(escapedDescription)]:\(option.long):\(valueSpec)'"
            } else {
                return "'{-\(short),--\(option.long)}[\(escapedDescription)]'"
            }
        } else {
            if option.takesValue {
                let valueSpec = generateValueSpec(for: option.valueType)
                return "'--\(option.long)[\(escapedDescription)]:\(option.long):\(valueSpec)'"
            } else {
                return "'--\(option.long)[\(escapedDescription)]'"
            }
        }
    }
    
    /// Generate value specification for option arguments
    /// - Parameter valueType: The value type
    /// - Returns: Zsh completion specification for the value
    private func generateValueSpec(for valueType: CompletionValueType) -> String {
        switch valueType {
        case .file:
            return "_files"
        case .directory:
            return "_files -/"
        case .deviceID, .busID:
            return "_usbipd_device_ids"
        case .ipAddress:
            return "_usbipd_ip_addresses"
        case .port:
            return "_usbipd_ports"
        case .string:
            return ""
        case .none:
            return ""
        }
    }
    
    /// Generate argument handling for command arguments
    /// - Parameter command: The command to handle
    /// - Returns: Zsh argument specifications
    private func generateArgumentHandling(for command: CompletionCommand) -> String {
        guard !command.arguments.isEmpty else {
            return ""
        }
        
        var argumentSpecs: [String] = []
        
        for (index, argument) in command.arguments.enumerated() {
            let argPosition = index + 2 // Position after command
            let required = argument.required ? "" : "::"
            _ = CompletionFormattingUtilities.escapeForShell(argument.description, shellType: shellType)
            
            switch argument.valueType {
            case .file:
                argumentSpecs.append("                    '\(argPosition)\(required):\(argument.name):_files'")
                
            case .directory:
                argumentSpecs.append("                    '\(argPosition)\(required):\(argument.name):_files -/'")
                
            case .deviceID, .busID:
                argumentSpecs.append("                    '\(argPosition)\(required):\(argument.name):_usbipd_device_ids'")
                
            case .ipAddress:
                argumentSpecs.append("                    '\(argPosition)\(required):\(argument.name):_usbipd_ip_addresses'")
                
            case .port:
                argumentSpecs.append("                    '\(argPosition)\(required):\(argument.name):_usbipd_ports'")
                
            case .string:
                if command.name == "help" {
                    argumentSpecs.append("                    '\(argPosition)\(required):\(argument.name):_usbipd_commands'")
                } else {
                    argumentSpecs.append("                    '\(argPosition)\(required):\(argument.name):'")
                }
                
            case .none:
                argumentSpecs.append("                    '\(argPosition)\(required):\(argument.name):'")
            }
        }
        
        return argumentSpecs.joined(separator: " \\\\\n")
    }
    
    /// Generate the function call and helper functions
    /// - Returns: Function call and helper function definitions
    private func generateFunctionCall() -> String {
        return """
        # Helper functions for dynamic completion
        _usbipd_device_ids() {
            local device_ids
            if (( $+commands[usbipd] )); then
                device_ids=(${(f)"$(usbipd list | awk 'NR>1 {print $1}' | grep -E '^[0-9]+-[0-9]+' | head -10 2>/dev/null)"})
            fi
            if [[ ${#device_ids[@]} -eq 0 ]]; then
                device_ids=('1-1' '1-2' '2-1')
            fi
            _describe 'device IDs' device_ids
        }
        
        _usbipd_ip_addresses() {
            local addresses=(
                'localhost:Local machine'
                '127.0.0.1:Local loopback'
                '192.168.1.100:Common LAN address'
            )
            _describe 'IP addresses' addresses
        }
        
        _usbipd_ports() {
            local ports=(
                '3240:Default USB/IP port'
                '3241:Alternative USB/IP port'
                '3242:Alternative USB/IP port'
                '8080:Common HTTP proxy port'
                '8000:Development server port'
            )
            _describe 'port numbers' ports
        }
        
        # Execute the main completion function
        _usbipd "$@"
        """
    }
}