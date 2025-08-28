// BashCompletionFormatter.swift
// Bash-specific completion script formatter

import Foundation

/// Bash completion formatter that generates bash-compatible completion scripts
public class BashCompletionFormatter: ShellCompletionFormatter {
    
    public let shellType = "bash"
    public let fileExtension = ""
    
    public init() {}
    
    /// Format completion data into a bash completion script
    /// - Parameter data: The completion data to format
    /// - Returns: Complete bash completion script
    public func formatCompletion(data: CompletionData) -> String {
        let header = CompletionFormattingUtilities.generateHeader(shellType: shellType, metadata: data.metadata)
        let completionFunction = generateCompletionFunction(data: data)
        let commandRegistration = generateCommandRegistration()
        
        return """
        \(header)
        \(completionFunction)
        
        \(commandRegistration)
        """
    }
    
    /// Format a command with its options and arguments for bash completion
    /// - Parameters:
    ///   - command: The command to format
    ///   - depth: Nesting depth (not used in bash, kept for protocol compliance)
    /// - Returns: Bash completion case statement for the command
    public func formatCommand(_ command: CompletionCommand, depth: Int = 0) -> String {
        let optionsString = formatOptions(command.options)
        let argumentHandling = generateArgumentHandling(for: command)
        
        return """
                \(command.name))
                    COMPREPLY+=($(compgen -W "\(optionsString)" -- "$cur"))
        \(argumentHandling)
                    ;;
        """
    }
    
    /// Format command options for bash completion
    /// - Parameter options: Array of options to format
    /// - Returns: Space-separated string of bash completion options
    public func formatOptions(_ options: [CompletionOption]) -> String {
        return CompletionFormattingUtilities.optionFlagsList(options)
    }
    
    /// Format dynamic value completion for bash
    /// - Parameter provider: Dynamic value provider
    /// - Returns: Bash command substitution for dynamic completion
    public func formatDynamicCompletion(_ provider: DynamicValueProvider) -> String {
        let escapedCommand = CompletionFormattingUtilities.escapeForShell(provider.command, shellType: shellType)
        let fallbackValues = provider.fallback.joined(separator: " ")
        
        return """
        # Dynamic completion for \(provider.context)
        if command -v usbipd >/dev/null 2>&1; then
            local dynamic_values
            dynamic_values=$(\(escapedCommand) 2>/dev/null || echo "\(fallbackValues)")
            COMPREPLY+=($(compgen -W "$dynamic_values" -- "$cur"))
        else
            COMPREPLY+=($(compgen -W "\(fallbackValues)" -- "$cur"))
        fi
        """
    }
    
    // MARK: - Private Implementation
    
    /// Generate the main bash completion function
    /// - Parameter data: Completion data
    /// - Returns: Complete bash completion function
    private func generateCompletionFunction(data: CompletionData) -> String {
        let commandCases = generateCommandCases(data: data)
        let globalOptions = formatOptions(data.globalOptions)
        let commandsList = CompletionFormattingUtilities.commandNamesList(data.commands)
        
        return """
        # Main bash completion function for usbipd
        _usbipd() {
            local cur prev words cword
            _init_completion || return
            
            # Handle global options
            case "$prev" in
                --version|-v)
                    return 0
                    ;;
                --config|-c)
                    _filedir
                    return 0
                    ;;
            esac
            
            # Handle subcommands
            local cmd_found=0
            local cmd=""
            for ((i=1; i < cword; i++)); do
                case "${words[i]}" in
                    --*|-*)
                        continue
                        ;;
                    *)
                        cmd="${words[i]}"
                        cmd_found=1
                        break
                        ;;
                esac
            done
            
            if [[ $cmd_found -eq 0 ]]; then
                # No command found, complete with commands and global options
                COMPREPLY=($(compgen -W "\(commandsList) \(globalOptions)" -- "$cur"))
                return 0
            fi
            
            # Handle command-specific completion
            case "$cmd" in
        \(commandCases)
                *)
                    # Unknown command, offer no completion
                    return 0
                    ;;
            esac
        }
        """
    }
    
    /// Generate case statements for all commands
    /// - Parameter data: Completion data
    /// - Returns: All command case statements
    private func generateCommandCases(data: CompletionData) -> String {
        return data.commands.map { command in
            formatCommand(command)
        }.joined(separator: "\n")
    }
    
    /// Generate argument-specific handling for a command
    /// - Parameter command: The command to handle
    /// - Returns: Bash completion logic for command arguments
    private func generateArgumentHandling(for command: CompletionCommand) -> String {
        guard !command.arguments.isEmpty else {
            return ""
        }
        
        var argumentHandling: [String] = []
        
        for (index, argument) in command.arguments.enumerated() {
            let argPosition = index + 2 // +2 because: 0=usbipd, 1=command, 2=first_arg
            
            switch argument.valueType {
            case .file:
                argumentHandling.append("""
                    # File completion for \(argument.name)
                    if [[ $cword -eq \(argPosition) ]]; then
                        _filedir
                        return 0
                    fi
                """)
                
            case .directory:
                argumentHandling.append("""
                    # Directory completion for \(argument.name)
                    if [[ $cword -eq \(argPosition) ]]; then
                        _filedir -d
                        return 0
                    fi
                """)
                
            case .deviceID, .busID:
                argumentHandling.append("""
                    # Device ID completion for \(argument.name)
                    if [[ $cword -eq \(argPosition) ]]; then
                        if command -v usbipd >/dev/null 2>&1; then
                            local devices
                            devices=$(usbipd list | awk 'NR>1 {print $1}' | grep -E '^[0-9]+-[0-9]+' | head -10 2>/dev/null || echo "1-1 1-2 2-1")
                            COMPREPLY=($(compgen -W "$devices" -- "$cur"))
                        else
                            COMPREPLY=($(compgen -W "1-1 1-2 2-1" -- "$cur"))
                        fi
                        return 0
                    fi
                """)
                
            case .ipAddress:
                argumentHandling.append("""
                    # IP address completion for \(argument.name)
                    if [[ $cword -eq \(argPosition) ]]; then
                        COMPREPLY=($(compgen -W "localhost 127.0.0.1 192.168.1.100" -- "$cur"))
                        return 0
                    fi
                """)
                
            case .port:
                argumentHandling.append("""
                    # Port number completion for \(argument.name)
                    if [[ $cword -eq \(argPosition) ]]; then
                        COMPREPLY=($(compgen -W "3240 3241 3242 8080 8000" -- "$cur"))
                        return 0
                    fi
                """)
                
            case .string, .none:
                if command.name == "help" {
                    // Special case: help command should complete with available commands
                    let commandsList = CompletionFormattingUtilities.commandNamesList(getAllCommands())
                    argumentHandling.append("""
                        # Command name completion for help
                        if [[ $cword -eq \(argPosition) ]]; then
                            COMPREPLY=($(compgen -W "\(commandsList)" -- "$cur"))
                            return 0
                        fi
                    """)
                }
                // For other string arguments, no specific completion
            }
        }
        
        return argumentHandling.joined(separator: "\n")
    }
    
    /// Generate the command registration line
    /// - Returns: Bash complete command registration
    private func generateCommandRegistration() -> String {
        return """
        # Register the completion function
        complete -F _usbipd usbipd
        """
    }
    
    /// Get all available commands for help completion
    /// - Returns: Array of basic command structures
    private func getAllCommands() -> [CompletionCommand] {
        return [
            CompletionCommand(name: "help", description: "Display help information"),
            CompletionCommand(name: "list", description: "List available USB devices"),
            CompletionCommand(name: "bind", description: "Bind a USB device to USB/IP"),
            CompletionCommand(name: "unbind", description: "Unbind a USB device from USB/IP"),
            CompletionCommand(name: "attach", description: "Attach a remote USB device"),
            CompletionCommand(name: "detach", description: "Detach a remote USB device"),
            CompletionCommand(name: "daemon", description: "Start USB/IP daemon"),
            CompletionCommand(name: "install-system-extension", description: "Install and register the System Extension"),
            CompletionCommand(name: "diagnose", description: "Run comprehensive installation and system diagnostics")
        ]
    }
}