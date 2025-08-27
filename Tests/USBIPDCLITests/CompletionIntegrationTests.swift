// CompletionIntegrationTests.swift
// Integration tests for end-to-end completion workflow and shell script syntax validation

import XCTest
import Foundation
@testable import USBIPDCLI
@testable import USBIPDCore
@testable import Common
// Note: SharedUtilities functions are used inline to avoid module dependency

final class CompletionIntegrationTests: XCTestCase {
    
    var tempDirectory: URL!
    var completionCommand: USBIPDCLI.CompletionCommand!
    
    override func setUp() {
        super.setUp()
        
        // Create temporary directory for test files
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("completion-integration-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
        
        // Initialize completion command with test dependencies
        completionCommand = USBIPDCLI.CompletionCommand()
    }
    
    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }
}

// MARK: - End-to-End Completion Workflow Tests

extension CompletionIntegrationTests {
    
    /// Test complete completion generation workflow
    func testCompleteCompletionGenerationWorkflow() throws {
        // Execute generate command
        let arguments = ["generate", "--output", tempDirectory.path]
        
        try completionCommand.execute(with: arguments)
        
        // Verify all shell completion files were created
        let bashFile = tempDirectory.appendingPathComponent("usbipd")
        let zshFile = tempDirectory.appendingPathComponent("_usbipd")
        let fishFile = tempDirectory.appendingPathComponent("usbipd.fish")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: bashFile.path), "Bash completion file should be created")
        XCTAssertTrue(FileManager.default.fileExists(atPath: zshFile.path), "Zsh completion file should be created")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fishFile.path), "Fish completion file should be created")
        
        // Verify files have content
        let bashContent = try String(contentsOf: bashFile, encoding: .utf8)
        let zshContent = try String(contentsOf: zshFile, encoding: .utf8)
        let fishContent = try String(contentsOf: fishFile, encoding: .utf8)
        
        XCTAssertFalse(bashContent.isEmpty, "Bash completion content should not be empty")
        XCTAssertFalse(zshContent.isEmpty, "Zsh completion content should not be empty")
        XCTAssertFalse(fishContent.isEmpty, "Fish completion content should not be empty")
        
        // Verify essential completion content is present
        verifyCompletionContent(bashContent, shell: "bash")
        verifyCompletionContent(zshContent, shell: "zsh")
        verifyCompletionContent(fishContent, shell: "fish")
    }
    
    /// Test completion generation for specific shells
    func testCompletionGenerationForSpecificShells() throws {
        // Generate only bash and zsh completions
        let arguments = ["generate", "--output", tempDirectory.path, "--shell", "bash", "--shell", "zsh"]
        
        try completionCommand.execute(with: arguments)
        
        // Verify only requested shells were generated
        let bashFile = tempDirectory.appendingPathComponent("usbipd")
        let zshFile = tempDirectory.appendingPathComponent("_usbipd")
        let fishFile = tempDirectory.appendingPathComponent("usbipd.fish")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: bashFile.path), "Bash completion should be generated")
        XCTAssertTrue(FileManager.default.fileExists(atPath: zshFile.path), "Zsh completion should be generated")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fishFile.path), "Fish completion should not be generated")
    }
    
    /// Test completion testing workflow
    func testCompletionTestingWorkflow() throws {
        // First generate completion scripts
        try completionCommand.execute(with: ["generate", "--output", tempDirectory.path])
        
        // Execute test command
        let testArguments = ["test"]
        
        // This should not throw as it's testing mock functionality
        try completionCommand.execute(with: testArguments)
    }
    
    /// Test completion validation workflow
    func testCompletionValidationWorkflow() throws {
        // First generate completion scripts
        try completionCommand.execute(with: ["generate", "--output", tempDirectory.path])
        
        // Execute validation command
        let validateArguments = ["validate", "--output", tempDirectory.path]
        
        try completionCommand.execute(with: validateArguments)
    }
    
    /// Test completion list functionality
    func testCompletionListWorkflow() throws {
        let listArguments = ["list"]
        
        try completionCommand.execute(with: listArguments)
    }
    
    /// Test help display functionality
    func testCompletionHelpWorkflow() throws {
        let helpArguments = ["--help"]
        
        try completionCommand.execute(with: helpArguments)
    }
}

// MARK: - Shell Script Syntax Validation Tests

extension CompletionIntegrationTests {
    
    /// Test bash completion script syntax validation
    func testBashCompletionSyntaxValidation() throws {
        // Generate bash completion
        try completionCommand.execute(with: ["generate", "--output", tempDirectory.path, "--shell", "bash"])
        
        let bashFile = tempDirectory.appendingPathComponent("usbipd")
        let bashContent = try String(contentsOf: bashFile, encoding: .utf8)
        
        // Validate bash syntax using basic checks
        let syntaxIssues = validateBashSyntax(bashContent)
        
        XCTAssertTrue(syntaxIssues.isEmpty, "Syntax issues: \(syntaxIssues)", file: #filePath, line: #line)
    }
    
    /// Test zsh completion script syntax validation
    func testZshCompletionSyntaxValidation() throws {
        // Generate zsh completion
        try completionCommand.execute(with: ["generate", "--output", tempDirectory.path, "--shell", "zsh"])
        
        let zshFile = tempDirectory.appendingPathComponent("_usbipd")
        let zshContent = try String(contentsOf: zshFile, encoding: .utf8)
        
        // Validate zsh syntax using basic checks
        let syntaxIssues = validateZshSyntax(zshContent)
        
        XCTAssertTrue(syntaxIssues.isEmpty, "Syntax issues: \(syntaxIssues)", file: #filePath, line: #line)
    }
    
    /// Test fish completion script syntax validation
    func testFishCompletionSyntaxValidation() throws {
        // Generate fish completion
        try completionCommand.execute(with: ["generate", "--output", tempDirectory.path, "--shell", "fish"])
        
        let fishFile = tempDirectory.appendingPathComponent("usbipd.fish")
        let fishContent = try String(contentsOf: fishFile, encoding: .utf8)
        
        // Validate fish syntax using basic checks
        let syntaxIssues = validateFishSyntax(fishContent)
        
        XCTAssertTrue(syntaxIssues.isEmpty, "Syntax issues: \(syntaxIssues)", file: #filePath, line: #line)
    }
    
    /// Test completion script includes expected commands
    func testCompletionScriptsIncludeExpectedCommands() throws {
        try completionCommand.execute(with: ["generate", "--output", tempDirectory.path])
        
        let expectedCommands = ["help", "list", "bind", "unbind", "attach", "detach", "daemon", "install-system-extension", "diagnose", "completion"]
        
        // Check bash completion
        let bashFile = tempDirectory.appendingPathComponent("usbipd")
        let bashContent = try String(contentsOf: bashFile, encoding: .utf8)
        
        for command in expectedCommands {
            XCTAssertTrue(
                bashContent.contains(command),
                "Bash completion should include command: \(command)"
            )
        }
        
        // Check zsh completion
        let zshFile = tempDirectory.appendingPathComponent("_usbipd")
        let zshContent = try String(contentsOf: zshFile, encoding: .utf8)
        
        for command in expectedCommands {
            XCTAssertTrue(
                zshContent.contains(command),
                "Zsh completion should include command: \(command)"
            )
        }
        
        // Check fish completion
        let fishFile = tempDirectory.appendingPathComponent("usbipd.fish")
        let fishContent = try String(contentsOf: fishFile, encoding: .utf8)
        
        for command in expectedCommands {
            XCTAssertTrue(
                fishContent.contains(command),
                "Fish completion should include command: \(command)"
            )
        }
    }
}

// MARK: - Error Handling Tests

extension CompletionIntegrationTests {
    
    /// Test invalid shell argument handling
    func testInvalidShellArgumentHandling() {
        let arguments = ["generate", "--shell", "invalid-shell"]
        
        XCTAssertThrowsError(try completionCommand.execute(with: arguments), "Should throw CommandLineError", file: #filePath, line: #line) { error in
            XCTAssertTrue(error is CommandLineError, "Error should be CommandLineError but got \(type(of: error))", file: #filePath, line: #line)
        }
    }
    
    /// Test invalid action argument handling
    func testInvalidActionArgumentHandling() {
        let arguments = ["invalid-action"]
        
        XCTAssertThrowsError(try completionCommand.execute(with: arguments), "Should throw CommandLineError", file: #filePath, line: #line) { error in
            XCTAssertTrue(error is CommandLineError, "Error should be CommandLineError but got \(type(of: error))", file: #filePath, line: #line)
        }
    }
    
    /// Test missing output directory handling
    func testMissingOutputDirectoryHandling() {
        let arguments = ["generate", "--output"]
        
        XCTAssertThrowsError(try completionCommand.execute(with: arguments), "Should throw CommandLineError", file: #filePath, line: #line) { error in
            XCTAssertTrue(error is CommandLineError, "Error should be CommandLineError but got \(type(of: error))", file: #filePath, line: #line)
        }
    }
    
    /// Test empty output directory validation
    func testEmptyOutputDirectoryValidation() {
        let arguments = ["generate", "--output", ""]
        
        XCTAssertThrowsError(try completionCommand.execute(with: arguments), "Should throw CommandLineError", file: #filePath, line: #line) { error in
            XCTAssertTrue(error is CommandLineError, "Error should be CommandLineError but got \(type(of: error))", file: #filePath, line: #line)
        }
    }
    
    /// Test validation with missing completion files
    func testValidationWithMissingCompletionFiles() {
        let emptyDirectory = tempDirectory.appendingPathComponent("empty")
        try! FileManager.default.createDirectory(at: emptyDirectory, withIntermediateDirectories: true, attributes: nil)
        
        let arguments = ["validate", "--output", emptyDirectory.path]
        
        XCTAssertThrowsError(try completionCommand.execute(with: arguments), "Should throw CommandHandlerError", file: #filePath, line: #line) { error in
            XCTAssertTrue(error is CommandHandlerError, "Error should be CommandHandlerError but got \(type(of: error))", file: #filePath, line: #line)
        }
    }
}

// MARK: - Performance Tests

extension CompletionIntegrationTests {
    
    /// Test completion generation performance
    func testCompletionGenerationPerformance() {
        let arguments = ["generate", "--output", tempDirectory.path]
        
        // Test completion generation performance within 5 seconds
        let expectation = XCTestExpectation(description: "Completion generation should complete within time limit")
        let startTime = Date()
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.completionCommand.execute(with: arguments)
                let executionTime = Date().timeIntervalSince(startTime)
                if executionTime <= 5.0 {
                    expectation.fulfill()
                } else {
                    XCTFail("Operation took \(executionTime)s, expected <= 5.0s", file: #filePath, line: #line)
                }
            } catch {
                XCTFail("Operation failed with error: \(error)", file: #filePath, line: #line)
            }
        }
        
        let waiterResult = XCTWaiter().wait(for: [expectation], timeout: 6.0)
        XCTAssertEqual(waiterResult, .completed, "Operation should complete within time limit", file: #filePath, line: #line)
    }
    
    /// Test completion validation performance
    func testCompletionValidationPerformance() throws {
        // First generate completion scripts
        try completionCommand.execute(with: ["generate", "--output", tempDirectory.path])
        
        let arguments = ["validate", "--output", tempDirectory.path]
        
        // Test completion validation performance within 3 seconds
        let expectation = XCTestExpectation(description: "Completion validation should complete within time limit")
        let startTime = Date()
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.completionCommand.execute(with: arguments)
                let executionTime = Date().timeIntervalSince(startTime)
                if executionTime <= 3.0 {
                    expectation.fulfill()
                } else {
                    XCTFail("Operation took \(executionTime)s, expected <= 3.0s", file: #filePath, line: #line)
                }
            } catch {
                XCTFail("Operation failed with error: \(error)", file: #filePath, line: #line)
            }
        }
        
        let waiterResult = XCTWaiter().wait(for: [expectation], timeout: 4.0)
        XCTAssertEqual(waiterResult, .completed, "Operation should complete within time limit", file: #filePath, line: #line)
    }
}

// MARK: - Helper Methods

extension CompletionIntegrationTests {
    
    /// Verify completion content contains essential elements
    /// - Parameters:
    ///   - content: Shell completion script content
    ///   - shell: Shell type (bash, zsh, fish)
    private func verifyCompletionContent(_ content: String, shell: String) {
        switch shell {
        case "bash":
            XCTAssertTrue(content.contains("_usbipd"), "Bash completion should contain main function")
            XCTAssertTrue(content.contains("complete -F _usbipd usbipd"), "Bash completion should register completion function")
            XCTAssertTrue(content.contains("COMPREPLY"), "Bash completion should use COMPREPLY")
            
        case "zsh":
            XCTAssertTrue(content.contains("#compdef usbipd"), "Zsh completion should have compdef directive")
            XCTAssertTrue(content.contains("_usbipd"), "Zsh completion should contain main function")
            XCTAssertTrue(content.contains("_describe"), "Zsh completion should use _describe")
            
        case "fish":
            XCTAssertTrue(content.contains("complete -c usbipd"), "Fish completion should register completions")
            XCTAssertTrue(content.contains("__fish_use_subcommand"), "Fish completion should use subcommand helper")
            
        default:
            XCTFail("Unknown shell type: \(shell)")
        }
        
        // Common checks for all shells
        XCTAssertTrue(content.contains("help"), "Completion should include help command")
        XCTAssertTrue(content.contains("list"), "Completion should include list command")
        XCTAssertTrue(content.contains("bind"), "Completion should include bind command")
    }
    
    /// Validate bash script syntax
    /// - Parameter content: Bash script content
    /// - Returns: Array of syntax issues
    private func validateBashSyntax(_ content: String) -> [String] {
        var issues: [String] = []
        
        // Check for basic syntax issues
        if content.count(of: "{") != content.count(of: "}") {
            issues.append("Unmatched braces in bash script")
        }
        
        if content.count(of: "(") != content.count(of: ")") {
            issues.append("Unmatched parentheses in bash script")
        }
        
        // Check for bash-specific requirements
        if !content.contains("complete -F") && !content.contains("complete -W") {
            issues.append("Bash completion should register completion function")
        }
        
        // Check for common bash completion patterns
        if content.contains("_init_completion") && !content.contains("|| return") {
            issues.append("Bash completion should handle _init_completion failure")
        }
        
        return issues
    }
    
    /// Validate zsh script syntax
    /// - Parameter content: Zsh script content
    /// - Returns: Array of syntax issues
    private func validateZshSyntax(_ content: String) -> [String] {
        var issues: [String] = []
        
        // Check for basic syntax issues
        if content.count(of: "{") != content.count(of: "}") {
            issues.append("Unmatched braces in zsh script")
        }
        
        if content.count(of: "(") != content.count(of: ")") {
            issues.append("Unmatched parentheses in zsh script")
        }
        
        // Check for zsh-specific requirements
        if !content.contains("#compdef") {
            issues.append("Zsh completion should have compdef directive")
        }
        
        // Check for common zsh completion patterns
        if !content.contains("_describe") && !content.contains("_arguments") {
            issues.append("Zsh completion should use _describe or _arguments")
        }
        
        return issues
    }
    
    /// Validate fish script syntax
    /// - Parameter content: Fish script content
    /// - Returns: Array of syntax issues
    private func validateFishSyntax(_ content: String) -> [String] {
        var issues: [String] = []
        
        // Check for fish-specific requirements
        if !content.contains("complete -c") {
            issues.append("Fish completion should use complete -c")
        }
        
        // Check for common fish completion patterns
        if !content.contains("__fish_use_subcommand") && content.contains("subcommand") {
            issues.append("Fish completion with subcommands should use __fish_use_subcommand")
        }
        
        // Basic fish syntax checks
        let lines = content.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }
            
            // Check for unterminated strings
            let singleQuoteCount = trimmedLine.count(of: "'")
            let doubleQuoteCount = trimmedLine.count(of: "\"")
            
            if singleQuoteCount % 2 != 0 {
                issues.append("Unterminated single quote on line \(index + 1)")
            }
            
            if doubleQuoteCount % 2 != 0 {
                issues.append("Unterminated double quote on line \(index + 1)")
            }
        }
        
        return issues
    }
}

// MARK: - String Extension for Character Counting

extension String {
    func count(of character: Character) -> Int {
        return self.reduce(0) { $1 == character ? $0 + 1 : $0 }
    }
}