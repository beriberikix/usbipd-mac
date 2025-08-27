// CompletionTests.swift
// Comprehensive unit tests for shell completion system

import XCTest
import Foundation
@testable import USBIPDCore
@testable import Common

final class CompletionTests: XCTestCase {
    
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        // Create temporary directory for test files
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }
}

// MARK: - CompletionData Tests

extension CompletionTests {
    
    func testCompletionDataInitialization() {
        let commands = [
            CompletionCommand(name: "test", description: "Test command")
        ]
        let globalOptions = [
            CompletionOption(long: "version", description: "Show version")
        ]
        let dynamicProviders = [
            DynamicValueProvider(context: "device-id", command: "echo test")
        ]
        let metadata = CompletionMetadata(version: "1.0.0")
        
        let completionData = CompletionData(
            commands: commands,
            globalOptions: globalOptions,
            dynamicProviders: dynamicProviders,
            metadata: metadata
        )
        
        XCTAssertEqual(completionData.commands.count, 1)
        XCTAssertEqual(completionData.commands[0].name, "test")
        XCTAssertEqual(completionData.globalOptions.count, 1)
        XCTAssertEqual(completionData.globalOptions[0].long, "version")
        XCTAssertEqual(completionData.dynamicProviders.count, 1)
        XCTAssertEqual(completionData.dynamicProviders[0].context, "device-id")
        XCTAssertEqual(completionData.metadata.version, "1.0.0")
    }
    
    func testCompletionDataCodable() {
        let completionData = CompletionData(
            commands: [CompletionCommand(name: "test", description: "Test")],
            globalOptions: [CompletionOption(long: "help", description: "Show help")],
            dynamicProviders: [DynamicValueProvider(context: "test", command: "echo")],
            metadata: CompletionMetadata(version: "1.0.0")
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try! encoder.encode(completionData)
        XCTAssertFalse(data.isEmpty)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decodedData = try! decoder.decode(CompletionData.self, from: data)
        
        XCTAssertEqual(decodedData.commands.count, completionData.commands.count)
        XCTAssertEqual(decodedData.commands[0].name, completionData.commands[0].name)
        XCTAssertEqual(decodedData.globalOptions[0].long, completionData.globalOptions[0].long)
        XCTAssertEqual(decodedData.metadata.version, completionData.metadata.version)
    }
}

// MARK: - CompletionExtractor Tests

extension CompletionTests {
    
    func testCompletionExtractorBasicExtraction() {
        let extractor = CompletionExtractor()
        let mockCommands = [
            MockCommand(name: "list", description: "List devices"),
            MockCommand(name: "bind", description: "Bind device")
        ]
        
        let completionData = extractor.extractCompletions(from: mockCommands)
        
        XCTAssertEqual(completionData.commands.count, 2)
        
        let listCommand = completionData.commands.first { $0.name == "list" }
        XCTAssertNotNil(listCommand)
        XCTAssertEqual(listCommand?.description, "List devices")
        
        let bindCommand = completionData.commands.first { $0.name == "bind" }
        XCTAssertNotNil(bindCommand)
        XCTAssertEqual(bindCommand?.description, "Bind device")
        
        // Should include global options
        XCTAssertGreaterThan(completionData.globalOptions.count, 0)
        
        // Should include dynamic providers
        XCTAssertGreaterThan(completionData.dynamicProviders.count, 0)
    }
    
    func testCompletionExtractorCommandOptions() {
        let extractor = CompletionExtractor()
        let mockCommand = MockCommand(name: "list", description: "List devices")
        
        let completionCommand = extractor.extractCommandMetadata(from: mockCommand)
        
        XCTAssertNotNil(completionCommand)
        XCTAssertEqual(completionCommand?.name, "list")
        XCTAssertEqual(completionCommand?.description, "List devices")
        
        // Should extract list command options
        let options = completionCommand?.options ?? []
        XCTAssertGreaterThan(options.count, 0)
        
        // Check for expected list options
        let localOption = options.first { $0.long == "local" }
        XCTAssertNotNil(localOption)
        XCTAssertEqual(localOption?.short, "l")
        
        let helpOption = options.first { $0.long == "help" }
        XCTAssertNotNil(helpOption)
        XCTAssertEqual(helpOption?.short, "h")
    }
    
    func testCompletionExtractorDynamicProviders() {
        let extractor = CompletionExtractor()
        let mockCommands = [MockCommand(name: "bind", description: "Bind device")]
        
        let completionData = extractor.extractCompletions(from: mockCommands)
        
        let deviceProvider = completionData.dynamicProviders.first { $0.context == "device-id" }
        XCTAssertNotNil(deviceProvider)
        XCTAssertFalse(deviceProvider?.command.isEmpty ?? true)
        XCTAssertGreaterThan(deviceProvider?.fallback.count ?? 0, 0)
        
        let ipProvider = completionData.dynamicProviders.first { $0.context == "ip-address" }
        XCTAssertNotNil(ipProvider)
        XCTAssertTrue((ipProvider?.fallback ?? []).contains("localhost"), "IP provider should contain localhost as fallback")
    }
}

// MARK: - Shell Formatter Tests

extension CompletionTests {
    
    func testBashCompletionFormatterBasic() {
        let formatter = BashCompletionFormatter()
        let completionData = createTestCompletionData()
        
        let script = formatter.formatCompletion(data: completionData)
        
        XCTAssertFalse(script.isEmpty)
        XCTAssertContains(script, "complete -F _usbipd usbipd")
        XCTAssertContains(script, "_usbipd()")
        XCTAssertContains(script, "test-command")
    }
    
    func testZshCompletionFormatterBasic() {
        let formatter = ZshCompletionFormatter()
        let completionData = createTestCompletionData()
        
        let script = formatter.formatCompletion(data: completionData)
        
        XCTAssertFalse(script.isEmpty)
        XCTAssertContains(script, "#compdef usbipd")
        XCTAssertContains(script, "_usbipd()")
        XCTAssertContains(script, "_describe 'commands'")
        XCTAssertContains(script, "test-command:Test command description")
    }
    
    func testFishCompletionFormatterBasic() {
        let formatter = FishCompletionFormatter()
        let completionData = createTestCompletionData()
        
        let script = formatter.formatCompletion(data: completionData)
        
        XCTAssertFalse(script.isEmpty)
        XCTAssertContains(script, "complete -c usbipd")
        XCTAssertContains(script, "__fish_use_subcommand")
        XCTAssertContains(script, "test-command")
        XCTAssertContains(script, "Test command description")
    }
    
    func testShellFormatterProperties() {
        let bashFormatter = BashCompletionFormatter()
        XCTAssertEqual(bashFormatter.shellType, "bash")
        XCTAssertEqual(bashFormatter.fileExtension, "")
        
        let zshFormatter = ZshCompletionFormatter()
        XCTAssertEqual(zshFormatter.shellType, "zsh")
        XCTAssertEqual(zshFormatter.fileExtension, "")
        
        let fishFormatter = FishCompletionFormatter()
        XCTAssertEqual(fishFormatter.shellType, "fish")
        XCTAssertEqual(fishFormatter.fileExtension, "fish")
    }
}

// MARK: - CompletionWriter Tests

extension CompletionTests {
    
    func testCompletionWriterBasicWriting() {
        let formatters = [MockShellFormatter()]
        let writer = CompletionWriter(formatters: formatters)
        let completionData = createTestCompletionData()
        
        let outputPath = tempDirectory.path
        
        XCTAssertNoThrow(try writer.writeCompletions(data: completionData, outputDirectory: outputPath))
        
        let summary = writer.getCompletionSummary(outputDirectory: outputPath)
        XCTAssertEqual(summary.outputDirectory, outputPath)
        XCTAssertEqual(summary.totalScripts, 1)
    }
    
    func testCompletionWriterDirectoryValidation() {
        let writer = CompletionWriter()
        
        // Test valid directory
        let validPath = tempDirectory.path
        XCTAssertNoThrow(try writer.validateOutputDirectory(path: validPath))
        
        // Test empty path
        XCTAssertThrowsError(try writer.validateOutputDirectory(path: ""))
        
        // Test too long path
        let longPath = String(repeating: "a", count: 2000)
        XCTAssertThrowsError(try writer.validateOutputDirectory(path: longPath))
    }
    
    func testCompletionWriterSummary() {
        let writer = CompletionWriter()
        let outputPath = tempDirectory.path
        
        // Create a test file
        let testFile = tempDirectory.appendingPathComponent("test.txt")
        try! "test content".write(to: testFile, atomically: true, encoding: .utf8)
        
        let summary = writer.getCompletionSummary(outputDirectory: outputPath)
        
        XCTAssertEqual(summary.outputDirectory, outputPath)
        XCTAssertGreaterThanOrEqual(summary.totalScripts, 0)
    }
}

// MARK: - CompletionFormattingUtilities Tests

extension CompletionTests {
    
    func testHeaderGeneration() {
        let metadata = CompletionMetadata(version: "1.0.0")
        let header = CompletionFormattingUtilities.generateHeader(shellType: "bash", metadata: metadata)
        
        XCTAssertContains(header, "Bash completion script")
        XCTAssertContains(header, "v1.0.0")
        XCTAssertFalse(header.isEmpty)
    }
    
    func testShellEscaping() {
        let testCases = [
            ("simple", "simple"),
            ("with spaces", "with spaces"),
            ("with'quote", "with\\'quote"),
            ("with\"doublequote", "with\\\"doublequote"),
            ("with$variable", "with\\$variable")
        ]
        
        for (input, expected) in testCases {
            let escaped = CompletionFormattingUtilities.escapeForShell(input, shellType: "bash")
            XCTAssertEqual(escaped, expected, "Failed to escape: \(input)")
        }
    }
    
    func testDescriptionFormatting() {
        let description = "Test description with special characters: $PATH and 'quotes'"
        
        let bashDesc = CompletionFormattingUtilities.formatDescription(description, for: "bash")
        let zshDesc = CompletionFormattingUtilities.formatDescription(description, for: "zsh")
        let fishDesc = CompletionFormattingUtilities.formatDescription(description, for: "fish")
        
        XCTAssertFalse(bashDesc.isEmpty)
        XCTAssertFalse(zshDesc.isEmpty)
        XCTAssertFalse(fishDesc.isEmpty)
        
        // Zsh should have brackets
        XCTAssertContains(zshDesc, "[")
        XCTAssertContains(zshDesc, "]")
    }
    
    func testCommandNamesList() {
        let commands = [
            CompletionCommand(name: "bind", description: "Bind device"),
            CompletionCommand(name: "list", description: "List devices"),
            CompletionCommand(name: "help", description: "Show help")
        ]
        
        let namesList = CompletionFormattingUtilities.commandNamesList(commands)
        
        XCTAssertContains(namesList, "bind")
        XCTAssertContains(namesList, "list")
        XCTAssertContains(namesList, "help")
    }
    
    func testOptionFlagsList() {
        let options = [
            CompletionOption(short: "h", long: "help", description: "Show help"),
            CompletionOption(long: "version", description: "Show version"),
            CompletionOption(short: "v", long: "verbose", description: "Verbose output")
        ]
        
        let flagsList = CompletionFormattingUtilities.optionFlagsList(options)
        
        XCTAssertContains(flagsList, "-h")
        XCTAssertContains(flagsList, "--help")
        XCTAssertContains(flagsList, "--version")
        XCTAssertContains(flagsList, "-v")
        XCTAssertContains(flagsList, "--verbose")
    }
    
    func testCompletionScriptValidation() {
        // Test valid bash script
        let validBashScript = """
        _usbipd() {
            local cur prev words cword
            _init_completion || return
            COMPREPLY=($(compgen -W "help list" -- "$cur"))
        }
        complete -F _usbipd usbipd
        """
        
        let bashIssues = CompletionFormattingUtilities.validateCompletionScript(validBashScript, for: "bash")
        XCTAssertEqual(bashIssues.count, 0)
        
        // Test invalid script with unmatched quotes
        let invalidScript = """
        _usbipd() {
            echo "unmatched quote
        }
        """
        
        let issues = CompletionFormattingUtilities.validateCompletionScript(invalidScript, for: "bash")
        XCTAssertGreaterThan(issues.count, 0)
    }
    
    func testFallbackCompletion() {
        let bashFallback = CompletionFormattingUtilities.generateFallbackCompletion(for: "bash", commandName: "usbipd")
        XCTAssertContains(bashFallback, "complete -W")
        XCTAssertContains(bashFallback, "usbipd")
        
        let zshFallback = CompletionFormattingUtilities.generateFallbackCompletion(for: "zsh", commandName: "usbipd")
        XCTAssertContains(zshFallback, "#compdef usbipd")
        
        let fishFallback = CompletionFormattingUtilities.generateFallbackCompletion(for: "fish", commandName: "usbipd")
        XCTAssertContains(fishFallback, "complete -c usbipd")
    }
}

// MARK: - Integration Tests

extension CompletionTests {
    
    func testEndToEndCompletionGeneration() {
        // Test complete workflow from command extraction to script writing
        let mockCommands = [
            MockCommand(name: "list", description: "List devices"),
            MockCommand(name: "bind", description: "Bind device"),
            MockCommand(name: "help", description: "Show help")
        ]
        
        let extractor = CompletionExtractor()
        let completionData = extractor.extractCompletions(from: mockCommands)
        
        let formatters: [ShellCompletionFormatter] = [
            BashCompletionFormatter(),
            ZshCompletionFormatter(),
            FishCompletionFormatter()
        ]
        
        let writer = CompletionWriter(formatters: formatters)
        let outputPath = tempDirectory.path
        
        XCTAssertNoThrow(try writer.writeCompletions(data: completionData, outputDirectory: outputPath))
        
        // Verify files were created
        let bashFile = tempDirectory.appendingPathComponent("usbipd")
        let zshFile = tempDirectory.appendingPathComponent("_usbipd")
        let fishFile = tempDirectory.appendingPathComponent("usbipd.fish")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: bashFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: zshFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fishFile.path))
        
        // Verify content is reasonable
        let bashContent = try! String(contentsOf: bashFile)
        XCTAssertContains(bashContent, "list")
        XCTAssertContains(bashContent, "bind")
        XCTAssertContains(bashContent, "help")
    }
}

// MARK: - Test Helpers

extension CompletionTests {
    
    private func createTestCompletionData() -> CompletionData {
        return CompletionData(
            commands: [
                CompletionCommand(
                    name: "test-command",
                    description: "Test command description",
                    options: [
                        CompletionOption(short: "h", long: "help", description: "Show help")
                    ],
                    arguments: [
                        CompletionArgument(name: "arg1", description: "First argument")
                    ]
                )
            ],
            globalOptions: [
                CompletionOption(long: "version", description: "Show version")
            ],
            dynamicProviders: [
                DynamicValueProvider(context: "test", command: "echo test", fallback: ["fallback"])
            ],
            metadata: CompletionMetadata(version: "1.0.0")
        )
    }
}

// MARK: - Mock Classes

private struct MockCommand: CompletableCommand {
    let name: String
    let description: String
}

private class MockShellFormatter: ShellCompletionFormatter {
    let shellType = "mock"
    let fileExtension = "mock"
    
    func formatCompletion(data: CompletionData) -> String {
        return "# Mock completion script for \(data.metadata.version)"
    }
    
    func formatCommand(_ command: USBIPDCore.CompletionCommand, depth: Int) -> String {
        return "mock command: \(command.name)"
    }
    
    func formatOptions(_ options: [CompletionOption]) -> String {
        return options.map { $0.long }.joined(separator: " ")
    }
    
    func formatDynamicCompletion(_ provider: DynamicValueProvider) -> String {
        return "mock dynamic: \(provider.context)"
    }
}

// MARK: - Test Utilities

extension XCTestCase {
    func XCTAssertContains(_ haystack: String, _ needle: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(haystack.contains(needle), "'\(haystack)' does not contain '\(needle)'", file: file, line: line)
    }
}