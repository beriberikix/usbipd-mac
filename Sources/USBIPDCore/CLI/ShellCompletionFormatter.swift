// ShellCompletionFormatter.swift
// Protocol and utilities for shell-specific completion script formatting

import Foundation

/// Protocol defining shell-specific completion formatting interface
public protocol ShellCompletionFormatter {
    
    /// The shell type this formatter targets (e.g., "bash", "zsh", "fish")
    var shellType: String { get }
    
    /// File extension for the generated completion script
    var fileExtension: String { get }
    
    /// Format completion data into a shell-specific completion script
    /// - Parameter data: The completion data to format
    /// - Returns: Shell-specific completion script as a string
    func formatCompletion(data: CompletionData) -> String
    
    /// Format a command with its options and arguments for completion
    /// - Parameters:
    ///   - command: The command to format
    ///   - depth: Nesting depth for subcommands (0 for top-level)
    /// - Returns: Formatted command completion string
    func formatCommand(_ command: CompletionCommand, depth: Int) -> String
    
    /// Format command options for completion
    /// - Parameter options: Array of options to format
    /// - Returns: Formatted options string
    func formatOptions(_ options: [CompletionOption]) -> String
    
    /// Format dynamic value completion
    /// - Parameter provider: Dynamic value provider
    /// - Returns: Formatted dynamic completion string
    func formatDynamicCompletion(_ provider: DynamicValueProvider) -> String
}

/// Shell-agnostic formatting utilities for completion scripts
public enum CompletionFormattingUtilities {
    
    /// Generate a completion script header with metadata
    /// - Parameters:
    ///   - shellType: Target shell type
    ///   - metadata: Completion metadata
    /// - Returns: Formatted header string
    public static func generateHeader(shellType: String, metadata: CompletionMetadata) -> String {
        let timestamp = ISO8601DateFormatter().string(from: metadata.generatedAt)
        
        return """
        # \(shellType.capitalized) completion script for usbipd
        # Generated on \(timestamp) by usbipd v\(metadata.version)
        # 
        # This file provides intelligent tab completion for the usbipd command-line tool.
        # It supports completion of commands, options, and dynamic values like device IDs.
        #
        # Installation:
        #   This file should be installed automatically via Homebrew to the appropriate
        #   completion directory for your shell.
        
        """
    }
    
    /// Escape special characters for shell safety
    /// - Parameters:
    ///   - text: Text to escape
    ///   - shellType: Target shell type for appropriate escaping
    /// - Returns: Escaped text safe for shell scripts
    public static func escapeForShell(_ text: String, shellType: String) -> String {
        switch shellType {
        case "bash", "zsh":
            // Escape single quotes and backslashes for bash/zsh
            return text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "`", with: "\\`")
            
        case "fish":
            // Fish has different escaping rules
            return text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            
        default:
            // Default conservative escaping
            return text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
    }
    
    /// Generate a list of command names for completion
    /// - Parameter commands: Array of commands
    /// - Returns: Space-separated list of command names
    public static func commandNamesList(_ commands: [CompletionCommand]) -> String {
        return commands.map { $0.name }.joined(separator: " ")
    }
    
    /// Generate option flags list for completion
    /// - Parameter options: Array of options
    /// - Returns: Space-separated list of option flags
    public static func optionFlagsList(_ options: [CompletionOption]) -> String {
        var flags: [String] = []
        
        for option in options {
            if let short = option.short {
                flags.append("-\(short)")
            }
            flags.append("--\(option.long)")
        }
        
        return flags.joined(separator: " ")
    }
    
    /// Check if a value type should use file completion
    /// - Parameter valueType: The value type to check
    /// - Returns: True if file completion should be used
    public static func shouldUseFileCompletion(for valueType: CompletionValueType) -> Bool {
        switch valueType {
        case .file, .directory:
            return true
        default:
            return false
        }
    }
    
    /// Check if a value type should use dynamic completion
    /// - Parameter valueType: The value type to check
    /// - Returns: True if dynamic completion should be used
    public static func shouldUseDynamicCompletion(for valueType: CompletionValueType) -> Bool {
        switch valueType {
        case .deviceID, .ipAddress, .port, .busID:
            return true
        default:
            return false
        }
    }
    
    /// Get the context key for dynamic completion
    /// - Parameter valueType: The value type
    /// - Returns: Context key for dynamic value provider lookup
    public static func dynamicCompletionContext(for valueType: CompletionValueType) -> String? {
        switch valueType {
        case .deviceID:
            return "device-id"
        case .busID:
            return "bus-id"
        case .ipAddress:
            return "ip-address"
        case .port:
            return "port"
        default:
            return nil
        }
    }
    
    /// Validate completion script syntax (basic checks)
    /// - Parameters:
    ///   - script: The completion script to validate
    ///   - shellType: Target shell type
    /// - Returns: Array of validation issues (empty if valid)
    public static func validateCompletionScript(_ script: String, for shellType: String) -> [String] {
        var issues: [String] = []
        
        // Check for common syntax issues
        if script.isEmpty {
            issues.append("Completion script is empty")
        }
        
        // Check for unmatched quotes
        let singleQuoteCount = script.filter { $0 == "'" }.count
        let doubleQuoteCount = script.filter { $0 == "\"" }.count
        
        if singleQuoteCount % 2 != 0 {
            issues.append("Unmatched single quotes detected")
        }
        
        if doubleQuoteCount % 2 != 0 {
            issues.append("Unmatched double quotes detected")
        }
        
        // Shell-specific validations
        switch shellType {
        case "bash":
            if !script.contains("complete") {
                issues.append("Bash completion script should contain 'complete' command")
            }
            
        case "zsh":
            if !script.contains("#compdef") && !script.contains("compctl") {
                issues.append("Zsh completion script should contain '#compdef' or 'compctl'")
            }
            
        case "fish":
            if !script.contains("complete") {
                issues.append("Fish completion script should contain 'complete' command")
            }
            
        default:
            // Unknown shell type - basic validation only
            break
        }
        
        return issues
    }
}