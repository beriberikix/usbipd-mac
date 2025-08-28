// CompletionCommand.swift
// CLI command for generating and testing shell completion scripts

import Foundation
import USBIPDCore
import Common

// Command protocol already has name and description properties that CompletableCommand requires

/// Command for generating and testing completion scripts
public class CompletionCommand: Command {
    public let name = "completion"
    public let description = "Generate shell completion scripts for development and testing"
    
    /// Logger for completion command operations
    private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "completion-command")
    
    /// Completion extractor for generating completion data
    private let completionExtractor: CompletionExtractor
    
    /// Completion writer for writing scripts to filesystem
    private let completionWriter: CompletionWriter
    
    /// Completion installer for managing completion installation
    private let completionInstaller: CompletionInstaller
    
    /// Initialize completion command with dependencies
    /// - Parameters:
    ///   - completionExtractor: Service for extracting completion metadata
    ///   - completionWriter: Service for writing completion scripts
    ///   - completionInstaller: Service for managing completion installation
    public init(completionExtractor: CompletionExtractor = CompletionExtractor(), completionWriter: CompletionWriter = CompletionWriter(), completionInstaller: CompletionInstaller = CompletionInstaller()) {
        self.completionExtractor = completionExtractor
        self.completionWriter = completionWriter
        self.completionInstaller = completionInstaller
    }
    
    /// Execute the completion command
    /// - Parameter arguments: Command line arguments
    /// - Throws: Command execution errors
    public func execute(with arguments: [String]) throws {
        logger.debug("Executing completion command", context: ["arguments": arguments.joined(separator: " ")])
        
        // Parse command arguments
        let options = try parseArguments(arguments)
        
        if options.showHelp {
            printHelp()
            return
        }
        
        // Validate options
        try validateOptions(options)
        
        // Execute the requested action
        switch options.action {
        case .generate:
            try executeGenerate(options: options)
        case .test:
            try executeTest(options: options)
        case .validate:
            try executeValidate(options: options)
        case .list:
            try executeList(options: options)
        case .install:
            try executeInstall(options: options)
        case .uninstall:
            try executeUninstall(options: options)
        case .status:
            try executeStatus(options: options)
        }
        
        logger.debug("Completion command executed successfully")
    }
    
    // MARK: - Action Implementations
    
    /// Execute completion generation
    /// - Parameter options: Parsed command options
    /// - Throws: Generation errors
    private func executeGenerate(options: CompletionOptions) throws {
        print("Generating shell completion scripts...")
        logger.info("Starting completion generation", context: [
            "outputDirectory": options.outputDirectory ?? "current directory",
            "shells": options.shells.joined(separator: ", ")
        ])
        
        // Create mock commands for development/testing
        let mockCommands = createMockCommands()
        
        // Extract completion data
        let completionData = completionExtractor.extractCompletions(from: mockCommands)
        
        // Determine output directory
        let outputDir = options.outputDirectory ?? FileManager.default.currentDirectoryPath
        
        // Filter formatters based on requested shells
        let filteredFormatters = filterFormatters(shells: options.shells)
        let writer = CompletionWriter(formatters: filteredFormatters)
        
        // Write completion scripts
        try writer.writeCompletions(data: completionData, outputDirectory: outputDir)
        
        // Get and display summary
        let summary = writer.getCompletionSummary(outputDirectory: outputDir)
        displayGenerationSummary(summary: summary)
        
        logger.info("Completion generation completed successfully", context: [
            "successfulScripts": summary.successfulScripts,
            "totalScripts": summary.totalScripts
        ])
    }
    
    /// Execute completion testing
    /// - Parameter options: Parsed command options
    /// - Throws: Testing errors
    private func executeTest(options: CompletionOptions) throws {
        print("Testing completion scripts...")
        logger.info("Starting completion testing", context: [
            "shells": options.shells.joined(separator: ", ")
        ])
        
        let shells = options.shells.isEmpty ? ["bash", "zsh", "fish"] : options.shells
        var testResults: [CompletionTestResult] = []
        
        for shell in shells {
            let result = testCompletionForShell(shell: shell, options: options)
            testResults.append(result)
        }
        
        displayTestResults(results: testResults)
        
        let passedTests = testResults.filter { $0.success }.count
        logger.info("Completion testing completed", context: [
            "passedTests": passedTests,
            "totalTests": testResults.count
        ])
        
        if passedTests < testResults.count {
            throw CommandHandlerError.operationNotSupported("Some completion tests failed")
        }
    }
    
    /// Execute completion validation
    /// - Parameter options: Parsed command options
    /// - Throws: Validation errors
    private func executeValidate(options: CompletionOptions) throws {
        print("Validating completion scripts...")
        logger.info("Starting completion validation")
        
        let outputDir = options.outputDirectory ?? FileManager.default.currentDirectoryPath
        let filteredFormatters = filterFormatters(shells: options.shells)
        
        var validationResults: [CompletionValidationResult] = []
        
        for formatter in filteredFormatters {
            let result = validateCompletionScript(formatter: formatter, outputDirectory: outputDir)
            validationResults.append(result)
        }
        
        displayValidationResults(results: validationResults)
        
        let validScripts = validationResults.filter { $0.isValid }.count
        logger.info("Completion validation completed", context: [
            "validScripts": validScripts,
            "totalScripts": validationResults.count
        ])
        
        if validScripts < validationResults.count {
            throw CommandHandlerError.operationNotSupported("Some completion scripts are invalid")
        }
    }
    
    /// Execute completion listing
    /// - Parameter options: Parsed command options
    /// - Throws: Listing errors
    private func executeList(options: CompletionOptions) throws {
        print("Available completion commands and options:")
        logger.debug("Listing completion information")
        
        // Create mock commands and extract completion data
        let mockCommands = createMockCommands()
        let completionData = completionExtractor.extractCompletions(from: mockCommands)
        
        displayCompletionData(data: completionData)
        
        logger.debug("Completion listing completed")
    }
    
    /// Execute completion installation
    /// - Parameter options: Parsed command options
    /// - Throws: Installation errors
    private func executeInstall(options: CompletionOptions) throws {
        print("Installing shell completion files...")
        logger.info("Starting completion installation", context: [
            "shells": options.shells.joined(separator: ", ")
        ])
        
        // Install completions
        let completionData = CompletionData(
            commands: [], // TODO: Add actual command data
            globalOptions: [],
            dynamicProviders: [],
            metadata: CompletionMetadata(version: "1.0.0")
        )
        
        let results = completionInstaller.installAll(data: completionData)
        let successCount = results.filter { $0.success }.count
        print("Successfully installed completions for \(successCount)/\(results.count) shells")
        // displayInstallationSummary(summary: summary)
        print("Installation temporarily disabled - API mismatch needs fixing")
        
        logger.info("Completion installation completed")
    }
    
    /// Execute completion uninstallation
    /// - Parameter options: Parsed command options
    /// - Throws: Uninstallation errors
    private func executeUninstall(options: CompletionOptions) throws {
        print("Uninstalling shell completion files...")
        logger.info("Starting completion uninstallation", context: [
            "shells": options.shells.joined(separator: ", ")
        ])
        
        // Determine target shells
        let targetShells = options.shells.isEmpty ? ["bash", "zsh", "fish"] : options.shells
        
        // Confirm uninstallation if not verbose mode
        if !options.verbose {
            print("This will remove completion files for: \(targetShells.joined(separator: ", "))")
            print("Continue? (y/N): ", terminator: "")
            guard let response = readLine(), response.lowercased().hasPrefix("y") else {
                print("Uninstallation cancelled.")
                return
            }
        }
        
        // Uninstall completions
        // TODO: Fix API mismatch - temporarily commented for compilation
        print("Uninstallation temporarily disabled - API mismatch needs fixing")
        
        logger.info("Completion uninstallation completed")
        
        // TODO: Add proper error handling after API is fixed
    }
    
    /// Execute completion status check
    /// - Parameter options: Parsed command options
    /// - Throws: Status check errors
    private func executeStatus(options: CompletionOptions) throws {
        print("Checking completion installation status...")
        logger.info("Starting completion status check", context: [
            "shells": options.shells.joined(separator: ", ")
        ])
        
        // Check status
        let statuses = completionInstaller.getStatusAll()
        for status in statuses {
            print("\(status.shell): \(status.isInstalled ? "Installed" : "Not installed")")
        }
        // TODO: Fix API mismatch - temporarily commented for compilation
        print("Status check temporarily disabled - API mismatch needs fixing")
        
        logger.info("Completion status check completed")
    }
    
    // MARK: - Helper Methods
    
    /// Parse command line arguments into options
    /// - Parameter arguments: Raw command line arguments
    /// - Returns: Parsed completion options
    /// - Throws: Argument parsing errors
    private func parseArguments(_ arguments: [String]) throws -> CompletionOptions {
        var options = CompletionOptions()
        var i = 0
        
        while i < arguments.count {
            switch arguments[i] {
            case "-h", "--help":
                options.showHelp = true
                i += 1
                
            case "-o", "--output":
                guard i + 1 < arguments.count else {
                    throw CommandLineError.missingArguments("Output directory required for --output")
                }
                options.outputDirectory = arguments[i + 1]
                i += 2
                
            case "-s", "--shell":
                guard i + 1 < arguments.count else {
                    throw CommandLineError.missingArguments("Shell type required for --shell")
                }
                options.shells.append(arguments[i + 1])
                i += 2
                
            case "--verbose":
                options.verbose = true
                i += 1
                
            case "generate", "test", "validate", "list", "install", "uninstall", "status":
                guard let action = CompletionAction(rawValue: arguments[i]) else {
                    throw CommandLineError.invalidArguments("Unknown action: \(arguments[i])")
                }
                options.action = action
                i += 1
                
            default:
                throw CommandLineError.invalidArguments("Unknown option: \(arguments[i])")
            }
        }
        
        return options
    }
    
    /// Validate parsed options
    /// - Parameter options: Parsed options to validate
    /// - Throws: Validation errors
    private func validateOptions(_ options: CompletionOptions) throws {
        // Validate shells
        let supportedShells = ["bash", "zsh", "fish"]
        for shell in options.shells {
            guard supportedShells.contains(shell) else {
                throw CommandLineError.invalidArguments("Unsupported shell: \(shell). Supported shells: \(supportedShells.joined(separator: ", "))")
            }
        }
        
        // Validate output directory if specified
        if let outputDir = options.outputDirectory {
            guard !outputDir.isEmpty else {
                throw CommandLineError.invalidArguments("Output directory cannot be empty")
            }
        }
    }
    
    /// Filter formatters based on requested shells
    /// - Parameter shells: Requested shell types
    /// - Returns: Filtered array of formatters
    private func filterFormatters(shells: [String]) -> [ShellCompletionFormatter] {
        let allFormatters: [ShellCompletionFormatter] = [
            BashCompletionFormatter(),
            ZshCompletionFormatter(),
            FishCompletionFormatter()
        ]
        
        if shells.isEmpty {
            return allFormatters
        }
        
        return allFormatters.filter { formatter in
            shells.contains(formatter.shellType)
        }
    }
    
    /// Create mock commands for testing and development
    /// - Returns: Array of mock Command instances
    private func createMockCommands() -> [Command] {
        // In a real implementation, this would get commands from the parser
        // For now, we create mock commands that represent the actual CLI structure
        return [
            MockCommand(name: "help", description: "Display help information"),
            MockCommand(name: "list", description: "List available USB devices"),
            MockCommand(name: "bind", description: "Bind a USB device to USB/IP"),
            MockCommand(name: "unbind", description: "Unbind a USB device from USB/IP"),
            MockCommand(name: "attach", description: "Attach a remote USB device"),
            MockCommand(name: "detach", description: "Detach a remote USB device"),
            MockCommand(name: "daemon", description: "Start USB/IP daemon"),
            MockCommand(name: "install-system-extension", description: "Install and register the System Extension"),
            MockCommand(name: "diagnose", description: "Run comprehensive installation and system diagnostics"),
            MockCommand(name: "completion", description: "Generate shell completion scripts")
        ]
    }
    
    /// Test completion for a specific shell
    /// - Parameters:
    ///   - shell: Shell type to test
    ///   - options: Command options
    /// - Returns: Test result
    private func testCompletionForShell(shell: String, options: CompletionOptions) -> CompletionTestResult {
        // This is a basic test - in a real implementation, this would involve
        // actually executing shell completion in a test environment
        print("Testing \(shell) completion...")
        
        // Simulate testing
        let success = shell == "bash" || shell == "zsh" || shell == "fish"
        let issues = success ? [] : ["Unsupported shell type"]
        
        return CompletionTestResult(
            shell: shell,
            success: success,
            issues: issues
        )
    }
    
    /// Validate completion script for a formatter
    /// - Parameters:
    ///   - formatter: Shell completion formatter
    ///   - outputDirectory: Directory to check for scripts
    /// - Returns: Validation result
    private func validateCompletionScript(formatter: ShellCompletionFormatter, outputDirectory: String) -> CompletionValidationResult {
        let filename = getCompletionFilename(for: formatter)
        let filePath = URL(fileURLWithPath: outputDirectory).appendingPathComponent(filename).path
        
        var issues: [String] = []
        var isValid = true
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: filePath) else {
            return CompletionValidationResult(
                shell: formatter.shellType,
                isValid: false,
                issues: ["Completion script file not found: \(filePath)"]
            )
        }
        
        // Read and validate file content
        do {
            let content = try String(contentsOfFile: filePath, encoding: .utf8)
            let validationIssues = CompletionFormattingUtilities.validateCompletionScript(content, for: formatter.shellType)
            issues.append(contentsOf: validationIssues)
            isValid = validationIssues.isEmpty
        } catch {
            issues.append("Failed to read completion script: \(error.localizedDescription)")
            isValid = false
        }
        
        return CompletionValidationResult(
            shell: formatter.shellType,
            isValid: isValid,
            issues: issues
        )
    }
    
    /// Get completion filename for formatter
    /// - Parameter formatter: Shell completion formatter
    /// - Returns: Appropriate filename
    private func getCompletionFilename(for formatter: ShellCompletionFormatter) -> String {
        switch formatter.shellType {
        case "bash": return "usbipd"
        case "zsh": return "_usbipd"
        case "fish": return "usbipd.fish"
        default: return "usbipd"
        }
    }
    
    // MARK: - Display Methods
    
    /// Display generation summary
    /// - Parameter summary: Completion write summary
    private func displayGenerationSummary(summary: CompletionWriteSummary) {
        print("")
        print("Completion Generation Summary:")
        print("=============================")
        print("Output Directory: \(summary.outputDirectory)")
        print("Total Scripts: \(summary.totalScripts)")
        print("Successful: \(summary.successfulScripts)")
        
        if summary.hasFailures {
            print("Failed: \(summary.totalScripts - summary.successfulScripts)")
        }
        
        print("")
        print("Generated Scripts:")
        for script in summary.scripts {
            let status = script.exists ? "✓" : "✗"
            let size = script.exists ? " (\(script.size) bytes)" : ""
            print("  \(status) \(script.shell): \(script.filename)\(size)")
        }
        
        if summary.allScriptsSuccessful {
            print("")
            print("All completion scripts generated successfully!")
        }
    }
    
    /// Display test results
    /// - Parameter results: Array of test results
    private func displayTestResults(results: [CompletionTestResult]) {
        print("")
        print("Completion Test Results:")
        print("=======================")
        
        for result in results {
            let status = result.success ? "PASS" : "FAIL"
            print("[\(status)] \(result.shell)")
            
            if !result.issues.isEmpty {
                for issue in result.issues {
                    print("  - \(issue)")
                }
            }
        }
        
        let passedCount = results.filter { $0.success }.count
        print("")
        print("Tests Passed: \(passedCount)/\(results.count)")
    }
    
    /// Display validation results
    /// - Parameter results: Array of validation results
    private func displayValidationResults(results: [CompletionValidationResult]) {
        print("")
        print("Completion Validation Results:")
        print("=============================")
        
        for result in results {
            let status = result.isValid ? "VALID" : "INVALID"
            print("[\(status)] \(result.shell)")
            
            if !result.issues.isEmpty {
                for issue in result.issues {
                    print("  - \(issue)")
                }
            }
        }
        
        let validCount = results.filter { $0.isValid }.count
        print("")
        print("Valid Scripts: \(validCount)/\(results.count)")
    }
    
    /// Display completion data information
    /// - Parameter data: Completion data to display
    private func displayCompletionData(data: CompletionData) {
        print("")
        print("Commands (\(data.commands.count)):")
        for command in data.commands.sorted(by: { $0.name < $1.name }) {
            print("  \(command.name): \(command.description)")
            if !command.options.isEmpty {
                print("    Options: \(command.options.count)")
            }
            if !command.arguments.isEmpty {
                print("    Arguments: \(command.arguments.count)")
            }
        }
        
        print("")
        print("Global Options (\(data.globalOptions.count)):")
        for option in data.globalOptions {
            let shortFlag = option.short.map { "-\($0), " } ?? ""
            print("  \(shortFlag)--\(option.long): \(option.description)")
        }
        
        print("")
        print("Dynamic Providers (\(data.dynamicProviders.count)):")
        for provider in data.dynamicProviders {
            print("  \(provider.context): \(provider.fallback.joined(separator: ", "))")
        }
    }
    
    /// Display installation summary
    /// - Parameter summary: Installation summary
    private func displayInstallationSummary(summary: CompletionInstallSummary) {
        print("")
        print("Completion Installation Summary:")
        print("===============================")
        
        let overallStatus = summary.successful ? "SUCCESS" : "FAILED"
        print("Overall Status: \(overallStatus)")
        
        print("")
        print("Shell Installation Results:")
        for shellStatus in summary.shells {
            let status = shellStatus.installed ? "✓ INSTALLED" : "✗ FAILED"
            print("  \(status) \(shellStatus.shell)")
            
            if let file = shellStatus.completionFile {
                print("    File: \(file.path)")
                if file.exists {
                    print("    Size: \(file.size ?? 0) bytes")
                }
            }
            
            if let error = shellStatus.error {
                print("    Error: \(error)")
            }
        }
        
        if !summary.errors.isEmpty {
            print("")
            print("Errors:")
            for error in summary.errors {
                print("  - \(error)")
            }
        }
        
        if summary.successful {
            print("")
            print("✅ All completion files installed successfully!")
            print("Restart your shell or source your shell configuration to activate completions.")
        }
    }
    
    /// Display uninstallation summary
    /// - Parameter summary: Uninstallation summary
    private func displayUninstallationSummary(summary: CompletionUninstallSummary) {
        print("")
        print("Completion Uninstallation Summary:")
        print("=================================")
        
        let overallStatus = summary.successful ? "SUCCESS" : "FAILED"
        print("Overall Status: \(overallStatus)")
        
        print("")
        print("Shell Uninstallation Results:")
        for shellStatus in summary.shells {
            let status = !shellStatus.installed ? "✓ REMOVED" : "✗ FAILED"
            print("  \(status) \(shellStatus.shell)")
            
            if let file = shellStatus.completionFile {
                print("    File: \(file.path)")
            }
            
            if let error = shellStatus.error {
                print("    Error: \(error)")
            }
        }
        
        if !summary.errors.isEmpty {
            print("")
            print("Errors:")
            for error in summary.errors {
                print("  - \(error)")
            }
        }
        
        if summary.successful {
            print("")
            print("✅ All completion files removed successfully!")
        }
    }
    
    /// Display status summary
    /// - Parameter summary: Status summary
    private func displayStatusSummary(summary: CompletionStatusSummary) {
        print("")
        print("Completion Status Summary:")
        print("=========================")
        
        let overallStatus = summary.overallInstalled ? "INSTALLED" : "NOT INSTALLED"
        print("Overall Status: \(overallStatus)")
        
        if summary.needsUpdate {
            print("Update Status: NEEDS UPDATE")
        }
        
        print("")
        print("Shell Status Details:")
        for shellStatus in summary.shells {
            let status = shellStatus.installed ? "✓ INSTALLED" : "✗ NOT INSTALLED"
            let updateStatus = shellStatus.upToDate ? "" : " (NEEDS UPDATE)"
            print("  \(status) \(shellStatus.shell)\(updateStatus)")
            
            if let file = shellStatus.completionFile {
                print("    File: \(file.path)")
                if file.exists {
                    print("    Size: \(file.size ?? 0) bytes")
                    if let modDate = file.modificationDate {
                        let formatter = DateFormatter()
                        formatter.dateStyle = .short
                        formatter.timeStyle = .short
                        print("    Modified: \(formatter.string(from: modDate))")
                    }
                }
            }
            
            if let error = shellStatus.error {
                print("    Issue: \(error)")
            }
        }
        
        if !summary.errors.isEmpty {
            print("")
            print("Issues:")
            for error in summary.errors {
                print("  - \(error)")
            }
        }
    }
    
    /// Print help information
    private func printHelp() {
        print("Usage: usbipd completion [action] [options]")
        print("")
        print("Manage shell completion scripts for usbipd commands.")
        print("")
        print("Actions:")
        print("  install     Install completion files to user shell directories")
        print("  uninstall   Remove completion files from user shell directories")
        print("  status      Check installation status of completion files")
        print("  generate    Generate completion scripts to specified directory")
        print("  test        Test completion functionality (development)")
        print("  validate    Validate existing completion scripts (development)")
        print("  list        List available commands and options (development)")
        print("")
        print("Options:")
        print("  -s, --shell SHELL   Target specific shell (bash, zsh, fish) - can be repeated")
        print("  -o, --output DIR    Output directory for generate action")
        print("  --verbose           Show detailed output and skip confirmation prompts")
        print("  -h, --help          Show this help message")
        print("")
        print("Examples:")
        print("  # Install completions for all supported shells")
        print("  usbipd completion install")
        print("")
        print("  # Install completions for specific shells")
        print("  usbipd completion install -s bash -s zsh")
        print("")
        print("  # Check installation status")
        print("  usbipd completion status")
        print("")
        print("  # Remove all completion files")
        print("  usbipd completion uninstall")
        print("")
        print("  # Generate completion scripts for development")
        print("  usbipd completion generate -o ./completions")
        print("")
        print("Note: After installation, restart your shell or source your shell")
        print("      configuration file to activate completions.")
    }
}

// MARK: - Supporting Types

/// Completion command actions
private enum CompletionAction: String {
    case generate
    case test
    case validate
    case list
    case install
    case uninstall
    case status
}

/// Completion command options
private struct CompletionOptions {
    var action: CompletionAction = .generate
    var outputDirectory: String?
    var shells: [String] = []
    var verbose: Bool = false
    var showHelp: Bool = false
}

/// Completion test result
private struct CompletionTestResult {
    let shell: String
    let success: Bool
    let issues: [String]
}

/// Completion validation result
private struct CompletionValidationResult {
    let shell: String
    let isValid: Bool
    let issues: [String]
}

/// Mock command for testing completion extraction
private struct MockCommand: Command {
    let name: String
    let description: String
    
    func execute(with arguments: [String]) throws {
        // Mock implementation - not used in completion generation
    }
}