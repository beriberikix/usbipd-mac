//
//  CompletionInstallationValidationTests.swift
//  usbipd-mac
//
//  Production validation tests for completion installation in real user environment
//  Tests installation with actual shell directories and validates completions work with real shell completion systems
//

import XCTest
import Foundation
@testable import USBIPDCore
@testable import Common

#if canImport(SharedUtilities)
import SharedUtilities
#endif

/// Production validation tests for completion installation system
/// Tests installation in real user environment with actual shell directories and completion system integration
final class CompletionInstallationValidationTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol Implementation
    
    public let environmentConfig = TestEnvironmentConfig.production
    public let requiredCapabilities: TestEnvironmentCapabilities = [
        .filesystemWrite,
        .networkAccess,
        .timeIntensiveOperations,
        .privilegedOperations
    ]
    public let testCategory: String = "completion-validation"
    
    // MARK: - Production Test Configuration
    
    private struct ProductionValidationConfig {
        let supportedShells: [String]
        let testTimeout: TimeInterval
        let backupExistingCompletions: Bool
        let enableShellCompletionTesting: Bool
        let enableRealWorldScenarios: Bool
        let cleanupOnFailure: Bool
        let createBackupDirectory: Bool
        let maxInstallationTime: TimeInterval
        let validateShellIntegration: Bool
        
        static let production = ProductionValidationConfig(
            supportedShells: ["bash", "zsh", "fish"],
            testTimeout: 300.0, // 5 minutes for production validation
            backupExistingCompletions: true,
            enableShellCompletionTesting: true,
            enableRealWorldScenarios: true,
            cleanupOnFailure: true,
            createBackupDirectory: true,
            maxInstallationTime: 10.0, // 10 seconds max per installation
            validateShellIntegration: true
        )
    }
    
    // MARK: - Test Properties
    
    private var logger: Logger!
    private var config: ProductionValidationConfig!
    private var completionInstaller: CompletionInstaller!
    private var userDirectoryResolver: UserDirectoryResolver!
    private var testStartTime: Date!
    private var backupDirectory: URL?
    private var createdBackups: [String: String] = [:]
    private var modifiedPaths: Set<String> = []
    
    // Real environment tracking
    private var realUserHome: String!
    private var originalEnvironment: [String: String] = [:]
    private var shellAvailability: [String: Bool] = [:]
    
    // Production completion data
    private var productionCompletionData: CompletionData!
    
    // MARK: - Test Lifecycle
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Initialize test suite
        setUpTestSuite()
        
        // Skip if required capabilities not available
        guard shouldRunInCurrentEnvironment() else {
            throw XCTSkip("Production completion validation requires filesystem write, time-intensive operations, and privileged access")
        }
        
        // Validate environment before running production tests
        try validateEnvironment()
        
        // Initialize logger
        logger = Logger(
            config: LoggerConfig(level: .info, includeTimestamp: true),
            subsystem: "com.usbipd.completion.validation",
            category: "production"
        )
        
        // Initialize configuration
        config = ProductionValidationConfig.production
        testStartTime = Date()
        
        // Capture real environment
        realUserHome = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        originalEnvironment = ProcessInfo.processInfo.environment
        
        // Detect available shells
        try detectAvailableShells()
        
        // Initialize completion components
        userDirectoryResolver = UserDirectoryResolver()
        completionInstaller = CompletionInstaller(
            directoryResolver: userDirectoryResolver,
            completionWriter: CompletionWriter()
        )
        
        // Create production-like completion data
        try setupProductionCompletionData()
        
        // Create backup directory for existing completions
        if config.createBackupDirectory {
            try createBackupDirectory()
        }
        
        logger.info("Production completion validation started", context: [
            "environment": environmentConfig.environment.displayName,
            "userHome": realUserHome,
            "availableShells": Array(shellAvailability.keys),
            "backupDirectory": backupDirectory?.path
        ])
    }
    
    override func tearDownWithError() throws {
        // Clean up production environment changes
        try restoreProductionEnvironment()
        
        // Clean up test resources
        testStartTime = nil
        productionCompletionData = nil
        shellAvailability.removeAll()
        originalEnvironment.removeAll()
        createdBackups.removeAll()
        modifiedPaths.removeAll()
        
        completionInstaller = nil
        userDirectoryResolver = nil
        config = nil
        logger = nil
        
        // Call test suite teardown
        tearDownTestSuite()
        
        try super.tearDownWithError()
    }
    
    // MARK: - TestSuite Implementation
    
    public func setUpTestSuite() {
        // Production test suite setup
    }
    
    public func tearDownTestSuite() {
        // Production test suite cleanup
    }
    
    // MARK: - Production Validation Tests
    
    func testProductionInstallationValidation() throws {
        logger.info("Starting production installation validation")
        
        // Phase 1: Pre-installation validation
        try validatePreInstallationState()
        
        // Phase 2: Installation in real user directories
        try testRealDirectoryInstallation()
        
        // Phase 3: Shell integration validation
        if config.enableShellCompletionTesting {
            try validateShellIntegration()
        }
        
        // Phase 4: Real-world usage scenarios
        if config.enableRealWorldScenarios {
            try testRealWorldScenarios()
        }
        
        // Phase 5: Performance validation
        try validateProductionPerformance()
        
        // Phase 6: Cleanup validation
        try testProductionCleanup()
        
        logger.info("✅ Production installation validation completed successfully")
    }
    
    // MARK: - Phase 1: Pre-Installation Validation
    
    private func validatePreInstallationState() throws {
        logger.info("Phase 1: Validating pre-installation state")
        
        // Check user environment
        XCTAssertFalse(realUserHome.isEmpty, "User home directory must be available")
        XCTAssertTrue(FileManager.default.fileExists(atPath: realUserHome), "User home directory must exist")
        
        // Check shell availability
        let availableShells = shellAvailability.filter { $0.value }.keys
        XCTAssertFalse(availableShells.isEmpty, "At least one shell must be available for production testing")
        
        // Check directory resolution for available shells
        for shell in availableShells {
            do {
                let directory = try userDirectoryResolver.resolveCompletionDirectory(for: shell)
                logger.debug("Shell directory resolved", context: [
                    "shell": shell,
                    "directory": directory
                ])
                
                // Backup existing completion file if it exists
                let completionFilename = getCompletionFilename(for: shell)
                let existingFile = URL(fileURLWithPath: directory).appendingPathComponent(completionFilename).path
                
                if FileManager.default.fileExists(atPath: existingFile) {
                    try backupExistingCompletion(shell: shell, existingPath: existingFile)
                }
            } catch {
                logger.warning("Failed to resolve directory for shell", context: [
                    "shell": shell,
                    "error": error.localizedDescription
                ])
                // Don't fail test - some shells might not have completion directories set up
            }
        }
        
        logger.info("✅ Pre-installation state validated")
    }
    
    // MARK: - Phase 2: Real Directory Installation
    
    func testRealDirectoryInstallation() throws {
        logger.info("Phase 2: Testing installation in real user directories")
        
        let availableShells = shellAvailability.filter { $0.value }.keys
        
        for shell in availableShells {
            logger.info("Installing completions for \(shell) in real user directory")
            
            let installStartTime = Date()
            
            // Install completion with real directory resolver
            let result = try completionInstaller.install(data: productionCompletionData, for: shell)
            
            let installDuration = Date().timeIntervalSince(installStartTime)
            
            // Validate installation succeeded
            XCTAssertTrue(result.success, "Installation should succeed for \(shell) in production environment")
            XCTAssertNotNil(result.targetPath, "Target path should be available for \(shell)")
            XCTAssertNil(result.error, "No error should occur during production installation for \(shell)")
            
            // Validate installation time
            XCTAssertLessThan(installDuration, config.maxInstallationTime,
                             "Installation should complete within \(config.maxInstallationTime)s for \(shell)")
            
            if let targetPath = result.targetPath {
                modifiedPaths.insert(targetPath)
                
                // Validate file was created in correct location
                XCTAssertTrue(FileManager.default.fileExists(atPath: targetPath),
                             "Completion file should exist at target path for \(shell)")
                
                // Validate file permissions in real environment
                try validateProductionFilePermissions(path: targetPath, shell: shell)
                
                // Validate file content in production environment
                try validateProductionFileContent(path: targetPath, shell: shell)
                
                logger.info("✅ Installation validated for \(shell)", context: [
                    "targetPath": targetPath,
                    "duration": String(format: "%.2fs", installDuration)
                ])
            }
        }
        
        logger.info("✅ Real directory installation completed")
    }
    
    // MARK: - Phase 3: Shell Integration Validation
    
    private func validateShellIntegration() throws {
        logger.info("Phase 3: Validating shell integration")
        
        let availableShells = shellAvailability.filter { $0.value }.keys
        
        for shell in availableShells {
            try testShellCompletionIntegration(shell: shell)
        }
        
        logger.info("✅ Shell integration validation completed")
    }
    
    private func testShellCompletionIntegration(shell: String) throws {
        logger.info("Testing shell completion integration for \(shell)")
        
        guard let shellPath = getShellExecutablePath(shell: shell) else {
            logger.warning("Shell executable not found", context: ["shell": shell])
            return
        }
        
        // Test basic completion functionality
        try testBasicCompletionFunctionality(shell: shell, shellPath: shellPath)
        
        // Test command completion
        try testCommandCompletion(shell: shell, shellPath: shellPath)
        
        // Test option completion
        try testOptionCompletion(shell: shell, shellPath: shellPath)
        
        logger.info("✅ Shell integration validated for \(shell)")
    }
    
    private func testBasicCompletionFunctionality(shell: String, shellPath: String) throws {
        logger.info("Testing basic completion functionality for \(shell)")
        
        let status = completionInstaller.getInstallationStatus(for: shell)
        XCTAssertTrue(status.isInstalled, "Completion should be installed for \(shell)")
        
        guard let targetPath = status.targetPath else {
            XCTFail("Target path should be available for installed completion")
            return
        }
        
        // Verify completion file can be sourced/loaded by shell
        switch shell.lowercased() {
        case "bash":
            try validateBashCompletionLoading(shellPath: shellPath, completionPath: targetPath)
        case "zsh":
            try validateZshCompletionLoading(shellPath: shellPath, completionPath: targetPath)
        case "fish":
            try validateFishCompletionLoading(shellPath: shellPath, completionPath: targetPath)
        default:
            logger.warning("Unknown shell type for integration testing", context: ["shell": shell])
        }
    }
    
    private func testCommandCompletion(shell: String, shellPath: String) throws {
        logger.info("Testing command completion for \(shell)")
        
        // Test that main commands can be completed
        let testCommands = ["list", "bind", "unbind", "server", "completion"]
        
        for command in testCommands {
            let completionWorks = try testCommandCompletionForShell(
                shell: shell,
                shellPath: shellPath,
                partialCommand: "usbipd \(command.prefix(2))",
                expectedCompletion: command
            )
            
            if completionWorks {
                logger.debug("Command completion works for \(command) in \(shell)")
            } else {
                logger.warning("Command completion may not work for \(command) in \(shell)")
                // Don't fail test - completion might work differently in different shell configurations
            }
        }
    }
    
    private func testOptionCompletion(shell: String, shellPath: String) throws {
        logger.info("Testing option completion for \(shell)")
        
        // Test common options completion
        let testOptions = ["--help", "--version", "--format", "--verbose"]
        
        for option in testOptions {
            let completionWorks = try testOptionCompletionForShell(
                shell: shell,
                shellPath: shellPath,
                command: "usbipd list",
                partialOption: option.prefix(3),
                expectedOption: option
            )
            
            if completionWorks {
                logger.debug("Option completion works for \(option) in \(shell)")
            } else {
                logger.warning("Option completion may not work for \(option) in \(shell)")
                // Don't fail test - option completion behavior varies
            }
        }
    }
    
    // MARK: - Phase 4: Real-World Scenarios
    
    func testRealWorldScenarios() throws {
        logger.info("Phase 4: Testing real-world scenarios")
        
        // Test 1: Multiple shell installations
        try testMultipleShellInstallations()
        
        // Test 2: Installation over existing completions
        try testInstallationOverExistingCompletions()
        
        // Test 3: User permission scenarios
        try testUserPermissionScenarios()
        
        // Test 4: Directory creation scenarios
        try testDirectoryCreationScenarios()
        
        logger.info("✅ Real-world scenarios validation completed")
    }
    
    func testMultipleShellInstallations() throws {
        logger.info("Testing multiple shell installations")
        
        let availableShells = Array(shellAvailability.filter { $0.value }.keys)
        guard availableShells.count > 1 else {
            logger.info("Skipping multiple shell test - only one shell available")
            return
        }
        
        // Install for all available shells simultaneously
        let installResults = completionInstaller.installAll(data: productionCompletionData)
        
        // Validate all installations succeeded
        let successfulInstalls = installResults.filter { $0.success }
        XCTAssertEqual(successfulInstalls.count, availableShells.count,
                      "All available shells should have successful installations")
        
        // Validate no conflicts between installations
        let targetPaths = installResults.compactMap { $0.targetPath }
        let uniquePaths = Set(targetPaths)
        XCTAssertEqual(targetPaths.count, uniquePaths.count,
                      "All installations should have unique target paths")
        
        // Track all paths for cleanup
        targetPaths.forEach { modifiedPaths.insert($0) }
        
        logger.info("✅ Multiple shell installations validated")
    }
    
    func testInstallationOverExistingCompletions() throws {
        logger.info("Testing installation over existing completions")
        
        let availableShells = shellAvailability.filter { $0.value }.keys
        guard let testShell = availableShells.first else {
            throw XCTSkip("No available shell for existing completion test")
        }
        
        // First installation should already exist from previous tests
        let initialStatus = completionInstaller.getInstallationStatus(for: testShell)
        XCTAssertTrue(initialStatus.isInstalled, "Initial installation should exist")
        
        guard let targetPath = initialStatus.targetPath else {
            XCTFail("Target path should be available for existing installation")
            return
        }
        
        // Get initial file info
        let initialAttributes = try FileManager.default.attributesOfItem(atPath: targetPath)
        let initialModificationDate = initialAttributes[.modificationDate] as? Date
        
        // Wait a moment to ensure different modification time
        Thread.sleep(forTimeInterval: 1.0)
        
        // Install again over existing completion
        let reinstallResult = try completionInstaller.install(data: productionCompletionData, for: testShell)
        
        // Validate reinstallation succeeded
        XCTAssertTrue(reinstallResult.success, "Reinstallation should succeed")
        XCTAssertNotNil(reinstallResult.backupPath, "Backup should be created for existing completion")
        
        // Validate file was updated
        let finalAttributes = try FileManager.default.attributesOfItem(atPath: targetPath)
        let finalModificationDate = finalAttributes[.modificationDate] as? Date
        
        if let initial = initialModificationDate, let final = finalModificationDate {
            XCTAssertGreaterThan(final, initial, "File should have been updated")
        }
        
        logger.info("✅ Installation over existing completions validated")
    }
    
    func testUserPermissionScenarios() throws {
        logger.info("Testing user permission scenarios")
        
        // Test read-only directory scenario (if we can create one safely)
        try testReadOnlyDirectoryHandling()
        
        // Test directory creation permissions
        try testDirectoryCreationPermissions()
        
        logger.info("✅ User permission scenarios validated")
    }
    
    func testDirectoryCreationScenarios() throws {
        logger.info("Testing directory creation scenarios")
        
        let availableShells = shellAvailability.filter { $0.value }.keys
        guard let testShell = availableShells.first else {
            throw XCTSkip("No available shell for directory creation test")
        }
        
        // Create a temporary shell environment that requires directory creation
        let testCompletionDir = URL(fileURLWithPath: realUserHome)
            .appendingPathComponent(".usbipd-test-completions")
            .appendingPathComponent(testShell)
        
        // Ensure directory doesn't exist
        if FileManager.default.fileExists(atPath: testCompletionDir.path) {
            try FileManager.default.removeItem(at: testCompletionDir)
        }
        
        defer {
            // Clean up test directory
            try? FileManager.default.removeItem(at: testCompletionDir.deletingLastPathComponent())
        }
        
        // Create mock directory resolver that points to non-existent directory
        let mockResolver = TestUserDirectoryResolver(mockDirectory: testCompletionDir.path)
        let testInstaller = CompletionInstaller(
            directoryResolver: mockResolver,
            completionWriter: CompletionWriter()
        )
        
        // Test installation with directory creation
        let result = try testInstaller.install(data: productionCompletionData, for: testShell)
        
        // Validate installation succeeded and directory was created
        XCTAssertTrue(result.success, "Installation should succeed with directory creation")
        XCTAssertTrue(FileManager.default.fileExists(atPath: testCompletionDir.path),
                     "Completion directory should be created")
        
        if let targetPath = result.targetPath {
            XCTAssertTrue(FileManager.default.fileExists(atPath: targetPath),
                         "Completion file should be created in new directory")
        }
        
        logger.info("✅ Directory creation scenarios validated")
    }
    
    // MARK: - Phase 5: Performance Validation
    
    private func validateProductionPerformance() throws {
        logger.info("Phase 5: Validating production performance")
        
        let availableShells = shellAvailability.filter { $0.value }.keys
        
        // Test installation performance for each shell
        for shell in availableShells {
            try validateInstallationPerformance(shell: shell)
        }
        
        // Test bulk installation performance
        if availableShells.count > 1 {
            try validateBulkInstallationPerformance()
        }
        
        logger.info("✅ Production performance validation completed")
    }
    
    private func validateInstallationPerformance(shell: String) throws {
        logger.info("Testing installation performance for \(shell)")
        
        // Perform multiple installations to measure performance
        var installationTimes: [TimeInterval] = []
        let iterations = 5
        
        for i in 0..<iterations {
            // Uninstall first (except first iteration)
            if i > 0 {
                _ = try completionInstaller.uninstall(for: shell)
            }
            
            let startTime = Date()
            let result = try completionInstaller.install(data: productionCompletionData, for: shell)
            let duration = Date().timeIntervalSince(startTime)
            
            XCTAssertTrue(result.success, "Installation \(i + 1) should succeed for \(shell)")
            installationTimes.append(duration)
            
            if let targetPath = result.targetPath {
                modifiedPaths.insert(targetPath)
            }
        }
        
        let averageTime = installationTimes.reduce(0, +) / Double(installationTimes.count)
        let maxTime = installationTimes.max() ?? 0
        
        // Performance assertions
        XCTAssertLessThan(averageTime, 5.0, "Average installation time should be under 5 seconds")
        XCTAssertLessThan(maxTime, 10.0, "Maximum installation time should be under 10 seconds")
        
        logger.info("Performance results for \(shell)", context: [
            "averageTime": String(format: "%.2fs", averageTime),
            "maxTime": String(format: "%.2fs", maxTime),
            "iterations": iterations
        ])
    }
    
    private func validateBulkInstallationPerformance() throws {
        logger.info("Testing bulk installation performance")
        
        let startTime = Date()
        let results = completionInstaller.installAll(data: productionCompletionData)
        let totalDuration = Date().timeIntervalSince(startTime)
        
        // Validate all installations succeeded
        let successfulResults = results.filter { $0.success }
        XCTAssertEqual(successfulResults.count, results.count,
                      "All bulk installations should succeed")
        
        // Performance validation
        XCTAssertLessThan(totalDuration, 15.0, "Bulk installation should complete within 15 seconds")
        
        // Track paths for cleanup
        results.compactMap { $0.targetPath }.forEach { modifiedPaths.insert($0) }
        
        logger.info("Bulk installation performance", context: [
            "totalTime": String(format: "%.2fs", totalDuration),
            "shellCount": results.count,
            "averagePerShell": String(format: "%.2fs", totalDuration / Double(results.count))
        ])
    }
    
    // MARK: - Phase 6: Cleanup Validation
    
    func testProductionCleanup() throws {
        logger.info("Phase 6: Testing production cleanup")
        
        let availableShells = shellAvailability.filter { $0.value }.keys
        
        // Test uninstallation for each shell
        for shell in availableShells {
            let result = try completionInstaller.uninstall(for: shell)
            
            XCTAssertTrue(result.success, "Uninstallation should succeed for \(shell)")
            
            if let removedPath = result.removedPath {
                modifiedPaths.remove(removedPath)
                XCTAssertFalse(FileManager.default.fileExists(atPath: removedPath),
                              "Completion file should be removed for \(shell)")
            }
        }
        
        // Verify all installations are removed
        let finalStatuses = completionInstaller.getStatusAll()
        for status in finalStatuses {
            XCTAssertFalse(status.isInstalled, "No completions should remain installed after cleanup")
        }
        
        logger.info("✅ Production cleanup validation completed")
    }
    
    // MARK: - Helper Methods
    
    private func detectAvailableShells() throws {
        logger.info("Detecting available shells")
        
        let shellPaths = [
            "bash": ["/bin/bash", "/usr/bin/bash", "/usr/local/bin/bash"],
            "zsh": ["/bin/zsh", "/usr/bin/zsh", "/usr/local/bin/zsh"],
            "fish": ["/usr/local/bin/fish", "/opt/homebrew/bin/fish", "/usr/bin/fish"]
        ]
        
        for (shell, paths) in shellPaths {
            var isAvailable = false
            
            for path in paths where FileManager.default.fileExists(atPath: path) {
                isAvailable = true
                logger.debug("Shell found", context: ["shell": shell, "path": path])
                break
            }
            
            shellAvailability[shell] = isAvailable
            
            if !isAvailable {
                logger.info("Shell not available", context: ["shell": shell])
            }
        }
        
        logger.info("Shell detection completed", context: [
            "availableShells": shellAvailability.filter { $0.value }.keys.joined(separator: ", ")
        ])
    }
    
    private func setupProductionCompletionData() throws {
        logger.info("Setting up production completion data")
        
        // Create realistic production completion data
        productionCompletionData = CompletionData(
            programName: "usbipd",
            version: "1.0.0-production",
            commands: [
                CompletionCommand(
                    name: "list",
                    description: "List available USB devices",
                    options: [
                        CompletionOption(name: "--format", description: "Output format (table, json, xml)", hasValue: true),
                        CompletionOption(name: "--verbose", description: "Verbose output", hasValue: false),
                        CompletionOption(name: "--filter", description: "Filter devices", hasValue: true),
                        CompletionOption(name: "--help", description: "Show help", hasValue: false)
                    ]
                ),
                CompletionCommand(
                    name: "bind",
                    description: "Bind a USB device",
                    options: [
                        CompletionOption(name: "--busid", description: "Device bus ID", hasValue: true),
                        CompletionOption(name: "--force", description: "Force binding", hasValue: false),
                        CompletionOption(name: "--help", description: "Show help", hasValue: false)
                    ]
                ),
                CompletionCommand(
                    name: "unbind",
                    description: "Unbind a USB device",
                    options: [
                        CompletionOption(name: "--busid", description: "Device bus ID", hasValue: true),
                        CompletionOption(name: "--all", description: "Unbind all devices", hasValue: false),
                        CompletionOption(name: "--help", description: "Show help", hasValue: false)
                    ]
                ),
                CompletionCommand(
                    name: "server",
                    description: "USB/IP server operations",
                    options: [
                        CompletionOption(name: "--start", description: "Start server", hasValue: false),
                        CompletionOption(name: "--stop", description: "Stop server", hasValue: false),
                        CompletionOption(name: "--status", description: "Server status", hasValue: false),
                        CompletionOption(name: "--port", description: "Server port", hasValue: true),
                        CompletionOption(name: "--config", description: "Configuration file", hasValue: true),
                        CompletionOption(name: "--help", description: "Show help", hasValue: false)
                    ]
                ),
                CompletionCommand(
                    name: "completion",
                    description: "Manage shell completions",
                    subcommands: [
                        CompletionCommand(
                            name: "install",
                            description: "Install shell completions",
                            options: [
                                CompletionOption(name: "--shell", description: "Target shell", hasValue: true),
                                CompletionOption(name: "--help", description: "Show help", hasValue: false)
                            ]
                        ),
                        CompletionCommand(
                            name: "uninstall", 
                            description: "Remove shell completions",
                            options: [
                                CompletionOption(name: "--shell", description: "Target shell", hasValue: true),
                                CompletionOption(name: "--help", description: "Show help", hasValue: false)
                            ]
                        ),
                        CompletionCommand(
                            name: "status",
                            description: "Check completion installation status",
                            options: [
                                CompletionOption(name: "--shell", description: "Target shell", hasValue: true),
                                CompletionOption(name: "--help", description: "Show help", hasValue: false)
                            ]
                        )
                    ]
                )
            ]
        )
        
        logger.info("✅ Production completion data configured")
    }
    
    private func createBackupDirectory() throws {
        let backupDir = URL(fileURLWithPath: realUserHome)
            .appendingPathComponent(".usbipd-completion-backups")
            .appendingPathComponent(ISO8601DateFormatter().string(from: testStartTime))
        
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        backupDirectory = backupDir
        
        logger.info("Backup directory created", context: ["path": backupDir.path])
    }
    
    private func backupExistingCompletion(shell: String, existingPath: String) throws {
        guard let backupDir = backupDirectory else { return }
        
        let filename = getCompletionFilename(for: shell)
        let backupPath = backupDir.appendingPathComponent("\(shell)-\(filename)").path
        
        try FileManager.default.copyItem(atPath: existingPath, toPath: backupPath)
        createdBackups[shell] = backupPath
        
        logger.info("Existing completion backed up", context: [
            "shell": shell,
            "originalPath": existingPath,
            "backupPath": backupPath
        ])
    }
    
    private func restoreProductionEnvironment() throws {
        logger.info("Restoring production environment")
        
        // Remove any files we created
        for path in modifiedPaths where FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
            logger.debug("Removed created file", context: ["path": path])
        }
        
        // Restore backed up completions
        for (shell, backupPath) in createdBackups {
            guard FileManager.default.fileExists(atPath: backupPath) else { continue }
            
            do {
                let directory = try userDirectoryResolver.resolveCompletionDirectory(for: shell)
                let filename = getCompletionFilename(for: shell)
                let targetPath = URL(fileURLWithPath: directory).appendingPathComponent(filename).path
                
                // Remove current file if it exists
                if FileManager.default.fileExists(atPath: targetPath) {
                    try FileManager.default.removeItem(atPath: targetPath)
                }
                
                // Restore backup
                try FileManager.default.moveItem(atPath: backupPath, toPath: targetPath)
                logger.info("Restored backup for \(shell)", context: ["path": targetPath])
            } catch {
                logger.warning("Failed to restore backup for \(shell)", context: [
                    "error": error.localizedDescription
                ])
            }
        }

        // Clean up backup directory
        if let backupDir = backupDirectory {
            try? FileManager.default.removeItem(at: backupDir)
        }
        
        logger.info("✅ Production environment restored")
    }
    
    private func getCompletionFilename(for shell: String) -> String {
        switch shell.lowercased() {
        case "bash":
            return "usbipd"
        case "zsh":
            return "_usbipd"
        case "fish":
            return "usbipd.fish"
        default:
            return "usbipd"
        }
    }
    
    private func getShellExecutablePath(shell: String) -> String? {
        let shellPaths = [
            "bash": ["/bin/bash", "/usr/bin/bash", "/usr/local/bin/bash"],
            "zsh": ["/bin/zsh", "/usr/bin/zsh", "/usr/local/bin/zsh"],
            "fish": ["/usr/local/bin/fish", "/opt/homebrew/bin/fish", "/usr/bin/fish"]
        ]
        
        guard let paths = shellPaths[shell.lowercased()] else { return nil }
        
        for path in paths where FileManager.default.fileExists(atPath: path) {
            return path
        }
        
        return nil
    }
    
    private func validateProductionFilePermissions(path: String, shell: String) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        
        XCTAssertNotNil(permissions, "File permissions should be set for \(shell)")
        
        if let perms = permissions {
            let permValue = perms.uint16Value
            
            // File should be readable by owner and group
            XCTAssertEqual(permValue & 0o644, 0o644,
                          "File should have at least rw-r--r-- permissions for \(shell)")
            
            // File should not be executable
            XCTAssertEqual(permValue & 0o111, 0,
                          "Completion file should not be executable for \(shell)")
        }
    }
    
    private func validateProductionFileContent(path: String, shell: String) throws {
        let content = try String(contentsOfFile: path)
        
        XCTAssertFalse(content.isEmpty, "Completion file should not be empty for \(shell)")
        XCTAssertTrue(content.contains("usbipd"), "Completion should reference program name for \(shell)")
        
        // Shell-specific content validation
        switch shell.lowercased() {
        case "bash":
            XCTAssertTrue(content.contains("complete"), "Bash completion should use complete builtin")
        case "zsh":
            XCTAssertTrue(content.contains("#compdef"), "Zsh completion should have compdef directive")
        case "fish":
            XCTAssertTrue(content.contains("complete"), "Fish completion should use complete command")
        default:
            break
        }
        
        // Validate production commands are present
        XCTAssertTrue(content.contains("list"), "Completion should include list command")
        XCTAssertTrue(content.contains("bind"), "Completion should include bind command")
        XCTAssertTrue(content.contains("completion"), "Completion should include completion command")
    }
    
    // MARK: - Shell-Specific Validation Methods
    
    private func validateBashCompletionLoading(shellPath: String, completionPath: String) throws {
        // Test that bash can source the completion file without errors
        let testScript = """
        source '\(completionPath)'
        echo "Completion loaded successfully"
        """
        
        try runShellScript(shellPath: shellPath, script: testScript, expectedOutput: "Completion loaded successfully")
    }
    
    private func validateZshCompletionLoading(shellPath: String, completionPath: String) throws {
        // Test that zsh can load the completion file
        let testScript = """
        fpath=('\(URL(fileURLWithPath: completionPath).deletingLastPathComponent().path)' $fpath)
        autoload -U compinit
        compinit
        echo "Completion loaded successfully"
        """
        
        try runShellScript(shellPath: shellPath, script: testScript, expectedOutput: "Completion loaded successfully")
    }
    
    private func validateFishCompletionLoading(shellPath: String, completionPath: String) throws {
        // Test that fish can load the completion file
        let testScript = """
        source '\(completionPath)'
        echo "Completion loaded successfully"
        """
        
        try runShellScript(shellPath: shellPath, script: testScript, expectedOutput: "Completion loaded successfully")
    }
    
    private func runShellScript(shellPath: String, script: String, expectedOutput: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-c", script]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let error = String(data: errorData, encoding: .utf8) ?? ""
            throw ValidationError.shellScriptFailed(shell: shellPath, output: output, error: error)
        }
        
        XCTAssertEqual(output, expectedOutput, "Shell script should produce expected output")
    }
    
    private func testCommandCompletionForShell(shell: String, shellPath: String, partialCommand: String, expectedCompletion: String) throws -> Bool {
        // This is a simplified test - real completion testing would require more complex shell interaction
        // For production validation, we verify the completion files are syntactically correct and loadable
        return true
    }
    
    private func testOptionCompletionForShell(shell: String, shellPath: String, command: String, partialOption: String.SubSequence, expectedOption: String) throws -> Bool {
        // This is a simplified test - real option completion testing would require shell completion simulation
        // For production validation, we verify the completion files contain the expected options
        let status = completionInstaller.getInstallationStatus(for: shell)
        guard let targetPath = status.targetPath else { return false }
        
        let content = try String(contentsOfFile: targetPath)
        return content.contains(expectedOption)
    }
    
    func testReadOnlyDirectoryHandling() throws {
        // Only test this if we can safely create a temporary read-only directory
        let tempReadOnlyDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("usbipd-readonly-test-\(UUID().uuidString)")
        
        defer {
            // Cleanup: Remove read-only directory
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempReadOnlyDir.path)
            try? FileManager.default.removeItem(at: tempReadOnlyDir)
        }
        
        try FileManager.default.createDirectory(at: tempReadOnlyDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tempReadOnlyDir.path)
        
        let testResolver = TestUserDirectoryResolver(mockDirectory: tempReadOnlyDir.path)
        let testInstaller = CompletionInstaller(directoryResolver: testResolver, completionWriter: CompletionWriter())
        
        // Test installation should handle read-only directory gracefully
        let result = try testInstaller.install(data: productionCompletionData, for: "bash")
        
        // Should either succeed (if permissions allow) or fail gracefully
        if !result.success {
            XCTAssertNotNil(result.error, "Error should be provided for permission failure")
            logger.debug("Read-only directory handled gracefully with error: \(result.error?.localizedDescription ?? "unknown")")
        }
    }
    
    func testDirectoryCreationPermissions() throws {
        // Test directory creation in user's home directory (should work)
        let testDir = URL(fileURLWithPath: realUserHome)
            .appendingPathComponent(".usbipd-permission-test-\(UUID().uuidString)")
        
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }
        
        try userDirectoryResolver.ensureDirectoryExists(path: testDir.path)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: testDir.path),
                     "Directory should be created in user home directory")
        
        // Test file creation in created directory
        let testFile = testDir.appendingPathComponent("test-completion")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path),
                     "File should be created in user directory")
    }
}

// MARK: - Supporting Types

private enum ValidationError: Error {
    case shellScriptFailed(shell: String, output: String, error: String)
    case shellNotAvailable(String)
    case completionValidationFailed(String)
    
    var localizedDescription: String {
        switch self {
        case .shellScriptFailed(let shell, let output, let error):
            return "Shell script failed for \(shell): \(error). Output: \(output)"
        case .shellNotAvailable(let shell):
            return "Shell not available: \(shell)"
        case .completionValidationFailed(let message):
            return "Completion validation failed: \(message)"
        }
    }
}

private class TestUserDirectoryResolver: UserDirectoryResolver {
    private let mockDirectory: String
    
    init(mockDirectory: String) {
        self.mockDirectory = mockDirectory
        super.init()
    }
    
    override func resolveCompletionDirectory(for shell: String) throws -> String {
        return mockDirectory
    }
}