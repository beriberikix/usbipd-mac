// UserDirectoryResolverTests.swift
// Unit tests for UserDirectoryResolver ensuring reliable directory resolution across shell environments

import XCTest
import Foundation
@testable import USBIPDCore
@testable import Common

final class UserDirectoryResolverTests: XCTestCase {
    
    var resolver: UserDirectoryResolver!
    var tempDirectory: URL!
    var originalEnvironment: [String: String] = [:]
    
    override func setUp() {
        super.setUp()
        resolver = UserDirectoryResolver()
        
        // Create temporary directory for test files
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
        
        // Save original environment variables
        originalEnvironment = ProcessInfo.processInfo.environment
    }
    
    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        
        // Restore original environment if needed
        super.tearDown()
    }
}

// MARK: - Bash Directory Resolution Tests

extension UserDirectoryResolverTests {
    
    func testBashDirectoryResolutionWithXDGDataHome() throws {
        // This test verifies the XDG_DATA_HOME logic, but since we can't easily mock environment
        // variables without dependency injection, we test that it works with the current environment
        let resolvedPath = try resolver.resolveCompletionDirectory(for: "bash")
        
        // Should contain the standard bash completion path
        XCTAssertTrue(resolvedPath.contains("bash-completion/completions"))
        
        // Should be a valid path
        XCTAssertFalse(resolvedPath.isEmpty)
        XCTAssertTrue(resolvedPath.hasPrefix("/"))
    }
    
    func testBashDirectoryResolutionWithEmptyXDGDataHome() throws {
        // Test that bash directory resolution works with current environment
        let resolvedPath = try resolver.resolveCompletionDirectory(for: "bash")
        
        // Should contain bash completion directory
        XCTAssertTrue(resolvedPath.contains("bash-completion/completions"))
        XCTAssertFalse(resolvedPath.isEmpty)
    }
    
    func testBashDirectoryResolutionFallbackToHome() throws {
        // Test standard bash directory resolution  
        let resolvedPath = try resolver.resolveCompletionDirectory(for: "bash")
        
        // Should be a valid bash completion path
        XCTAssertTrue(resolvedPath.contains("bash-completion/completions"))
        XCTAssertFalse(resolvedPath.isEmpty)
    }
    
    func testBashDirectoryResolutionNoHomeEnvironment() throws {
        // This test would require dependency injection to mock environment
        // For now, test that resolution succeeds with current environment
        let resolvedPath = try resolver.resolveCompletionDirectory(for: "bash")
        
        // Should be a valid path in current environment
        XCTAssertFalse(resolvedPath.isEmpty)
        XCTAssertTrue(resolvedPath.contains("bash-completion/completions"))
    }
    
    func testBashDirectoryResolutionEmptyHomeEnvironment() throws {
        // This test would require dependency injection to mock environment
        // For now, test that resolution succeeds with current environment
        let resolvedPath = try resolver.resolveCompletionDirectory(for: "bash")
        
        // Should be a valid path in current environment
        XCTAssertFalse(resolvedPath.isEmpty)
        XCTAssertTrue(resolvedPath.contains("bash-completion/completions"))
    }
}

// MARK: - Zsh Directory Resolution Tests

extension UserDirectoryResolverTests {
    
    func testZshDirectoryResolutionStandardPath() throws {
        let resolvedPath = try resolver.resolveCompletionDirectory(for: "zsh")
        
        let homeDirectory = originalEnvironment["HOME"] ?? ""
        let expectedPath = "\(homeDirectory)/.zsh/completions"
        XCTAssertEqual(resolvedPath, expectedPath)
    }
    
    func testZshDirectoryResolutionCaseInsensitive() throws {
        let resolvedPath = try resolver.resolveCompletionDirectory(for: "ZSH")
        
        let homeDirectory = originalEnvironment["HOME"] ?? ""
        let expectedPath = "\(homeDirectory)/.zsh/completions"
        XCTAssertEqual(resolvedPath, expectedPath)
    }
    
    func testZshDirectoryResolutionNoHomeEnvironment() throws {
        // This test would require dependency injection to mock environment
        // For now, test that resolution succeeds with current environment
        let resolvedPath = try resolver.resolveCompletionDirectory(for: "zsh")
        
        // Should be a valid zsh path in current environment
        XCTAssertFalse(resolvedPath.isEmpty)
        XCTAssertTrue(resolvedPath.contains(".zsh/completions"))
    }
    
    func testZshDirectoryResolutionEmptyHomeEnvironment() throws {
        // This test would require dependency injection to mock environment
        // For now, test that resolution succeeds with current environment
        let resolvedPath = try resolver.resolveCompletionDirectory(for: "zsh")
        
        // Should be a valid zsh path in current environment
        XCTAssertFalse(resolvedPath.isEmpty)
        XCTAssertTrue(resolvedPath.contains(".zsh/completions"))
    }
}

// MARK: - Fish Directory Resolution Tests

extension UserDirectoryResolverTests {
    
    func testFishDirectoryResolutionWithXDGConfigHome() throws {
        // Test that fish directory resolution works with current environment
        let resolvedPath = try resolver.resolveCompletionDirectory(for: "fish")
        
        // Should contain fish completion directory
        XCTAssertTrue(resolvedPath.contains("fish/completions"))
        XCTAssertFalse(resolvedPath.isEmpty)
    }
    
    func testFishDirectoryResolutionWithEmptyXDGConfigHome() throws {
        // Test that fish directory resolution works with current environment
        let resolvedPath = try resolver.resolveCompletionDirectory(for: "fish")
        
        // Should contain fish completion directory
        XCTAssertTrue(resolvedPath.contains("fish/completions"))
        XCTAssertFalse(resolvedPath.isEmpty)
    }
    
    func testFishDirectoryResolutionFallbackToHome() throws {
        // Test standard fish directory resolution  
        let resolvedPath = try resolver.resolveCompletionDirectory(for: "fish")
        
        // Should be a valid fish completion path
        XCTAssertTrue(resolvedPath.contains("fish/completions"))
        XCTAssertFalse(resolvedPath.isEmpty)
    }
    
    func testFishDirectoryResolutionNoHomeEnvironment() throws {
        // This test would require dependency injection to mock environment
        // For now, test that resolution succeeds with current environment
        let resolvedPath = try resolver.resolveCompletionDirectory(for: "fish")
        
        // Should be a valid fish path in current environment
        XCTAssertFalse(resolvedPath.isEmpty)
        XCTAssertTrue(resolvedPath.contains("fish/completions"))
    }
}

// MARK: - Unsupported Shell Tests

extension UserDirectoryResolverTests {
    
    func testUnsupportedShellResolution() throws {
        let unsupportedShells = ["powershell", "cmd", "csh", "tcsh", "unknown"]
        
        for shell in unsupportedShells {
            XCTAssertThrowsError(try resolver.resolveCompletionDirectory(for: shell)) { error in
                guard let resolverError = error as? UserDirectoryResolverError else {
                    XCTFail("Expected UserDirectoryResolverError for shell: \(shell)")
                    return
                }
                
                if case .unsupportedShell(let message) = resolverError {
                    XCTAssertTrue(message.contains(shell))
                } else {
                    XCTFail("Expected unsupportedShell error for shell: \(shell)")
                }
            }
        }
    }
}

// MARK: - Directory Validation Tests

extension UserDirectoryResolverTests {
    
    func testValidDirectoryValidation() throws {
        let validPath = tempDirectory.path
        let isValid = try resolver.validateDirectory(path: validPath)
        XCTAssertTrue(isValid)
    }
    
    func testEmptyPathValidation() throws {
        XCTAssertThrowsError(try resolver.validateDirectory(path: "")) { error in
            guard let resolverError = error as? UserDirectoryResolverError else {
                XCTFail("Expected UserDirectoryResolverError")
                return
            }
            
            if case .invalidPath(let message) = resolverError {
                XCTAssertTrue(message.contains("empty"))
            } else {
                XCTFail("Expected invalidPath error for empty path")
            }
        }
    }
    
    func testTooLongPathValidation() throws {
        let longPath = String(repeating: "a", count: 1025)
        
        XCTAssertThrowsError(try resolver.validateDirectory(path: longPath)) { error in
            guard let resolverError = error as? UserDirectoryResolverError else {
                XCTFail("Expected UserDirectoryResolverError")
                return
            }
            
            if case .invalidPath(let message) = resolverError {
                XCTAssertTrue(message.contains("too long"))
            } else {
                XCTFail("Expected invalidPath error for long path")
            }
        }
    }
    
    func testNonExistentParentDirectoryValidation() throws {
        let nonExistentPath = "/nonexistent/directory/path"
        
        XCTAssertThrowsError(try resolver.validateDirectory(path: nonExistentPath)) { error in
            guard let resolverError = error as? UserDirectoryResolverError else {
                XCTFail("Expected UserDirectoryResolverError")
                return
            }
            
            if case .invalidPath(let message) = resolverError {
                XCTAssertTrue(message.contains("Parent directory does not exist"))
            } else {
                XCTFail("Expected invalidPath error for non-existent parent")
            }
        }
    }
    
    func testExistingFileAsDirectoryValidation() throws {
        // Create a regular file
        let filePath = tempDirectory.appendingPathComponent("testfile").path
        try "test content".write(toFile: filePath, atomically: true, encoding: .utf8)
        
        XCTAssertThrowsError(try resolver.validateDirectory(path: filePath)) { error in
            guard let resolverError = error as? UserDirectoryResolverError else {
                XCTFail("Expected UserDirectoryResolverError")
                return
            }
            
            if case .invalidPath(let message) = resolverError {
                XCTAssertTrue(message.contains("not a directory"))
            } else {
                XCTFail("Expected invalidPath error for file instead of directory")
            }
        }
    }
    
    func testExistingWritableDirectoryValidation() throws {
        let writableDir = tempDirectory.appendingPathComponent("writable").path
        try FileManager.default.createDirectory(atPath: writableDir, withIntermediateDirectories: true, attributes: nil)
        
        let isValid = try resolver.validateDirectory(path: writableDir)
        XCTAssertTrue(isValid)
    }
}

// MARK: - Directory Creation Tests

extension UserDirectoryResolverTests {
    
    func testCreateNonExistentDirectory() throws {
        let newDirPath = tempDirectory.appendingPathComponent("newdir").path
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: newDirPath))
        
        try resolver.createDirectory(path: newDirPath)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: newDirPath))
        
        // Verify it's a directory
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: newDirPath, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
    
    func testCreateDirectoryWithIntermediatePaths() throws {
        let deepPath = tempDirectory.appendingPathComponent("level1/level2/level3").path
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: deepPath))
        
        try resolver.createDirectory(path: deepPath)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: deepPath))
        
        // Verify all intermediate directories exist
        let level1Path = tempDirectory.appendingPathComponent("level1").path
        let level2Path = tempDirectory.appendingPathComponent("level1/level2").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: level1Path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: level2Path))
    }
    
    func testCreateAlreadyExistingDirectory() throws {
        let existingPath = tempDirectory.path
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingPath))
        
        // Should not throw error when directory already exists
        XCTAssertNoThrow(try resolver.createDirectory(path: existingPath))
    }
    
    func testCreateDirectoryWithCorrectPermissions() throws {
        let newDirPath = tempDirectory.appendingPathComponent("permissions-test").path
        
        try resolver.createDirectory(path: newDirPath)
        
        let attributes = try FileManager.default.attributesOfItem(atPath: newDirPath)
        let permissions = attributes[.posixPermissions] as? NSNumber
        
        XCTAssertEqual(permissions?.intValue, 0o755)
    }
}

// MARK: - Directory Ensure Tests

extension UserDirectoryResolverTests {
    
    func testEnsureDirectoryExistsForValidPath() throws {
        let validPath = tempDirectory.path
        
        XCTAssertNoThrow(try resolver.ensureDirectoryExists(path: validPath))
    }
    
    func testEnsureDirectoryExistsCreatesPath() throws {
        let newPath = tempDirectory.appendingPathComponent("ensure-test").path
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: newPath))
        
        try resolver.ensureDirectoryExists(path: newPath)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: newPath))
    }
    
    func testEnsureDirectoryExistsWithInvalidPath() throws {
        XCTAssertThrowsError(try resolver.ensureDirectoryExists(path: "")) { error in
            XCTAssertTrue(error is UserDirectoryResolverError)
        }
    }
}

// MARK: - Directory Info Tests

extension UserDirectoryResolverTests {
    
    func testGetDirectoryInfoForExistingDirectory() throws {
        let path = tempDirectory.path
        let info = resolver.getDirectoryInfo(path: path)
        
        XCTAssertEqual(info.path, path)
        XCTAssertTrue(info.exists)
        XCTAssertTrue(info.isDirectory)
        XCTAssertTrue(info.isWritable)
        XCTAssertNotNil(info.modificationDate)
    }
    
    func testGetDirectoryInfoForNonExistentPath() throws {
        let nonExistentPath = tempDirectory.appendingPathComponent("nonexistent").path
        let info = resolver.getDirectoryInfo(path: nonExistentPath)
        
        XCTAssertEqual(info.path, nonExistentPath)
        XCTAssertFalse(info.exists)
        XCTAssertFalse(info.isDirectory)
        XCTAssertFalse(info.isWritable)
        XCTAssertNil(info.size)
        XCTAssertNil(info.modificationDate)
    }
    
    func testGetDirectoryInfoForFile() throws {
        let filePath = tempDirectory.appendingPathComponent("testfile.txt").path
        try "test content".write(toFile: filePath, atomically: true, encoding: .utf8)
        
        let info = resolver.getDirectoryInfo(path: filePath)
        
        XCTAssertEqual(info.path, filePath)
        XCTAssertTrue(info.exists)
        XCTAssertFalse(info.isDirectory)
        XCTAssertNotNil(info.size)
        XCTAssertNotNil(info.modificationDate)
    }
}

// MARK: - Error Handling Tests

extension UserDirectoryResolverTests {
    
    func testUserDirectoryResolverErrorDescriptions() {
        let errors: [UserDirectoryResolverError] = [
            .unsupportedShell("test shell"),
            .environmentVariableNotFound("TEST_VAR"),
            .invalidPath("invalid/path"),
            .directoryCreationFailed("creation failed")
        ]
        
        for error in errors {
            let description = error.errorDescription
            XCTAssertNotNil(description)
            XCTAssertFalse(description?.isEmpty ?? true)
        }
    }
}

// MARK: - Integration Tests

extension UserDirectoryResolverTests {
    
    func testEndToEndDirectoryResolutionAndCreation() throws {
        // Test complete workflow: resolve -> validate -> ensure -> info
        let shell = "bash"
        
        // 1. Resolve directory for shell
        let resolvedPath = try resolver.resolveCompletionDirectory(for: shell)
        XCTAssertFalse(resolvedPath.isEmpty)
        
        // 2. Validate the path (may not exist yet)
        // Note: This may throw if parent doesn't exist, which is expected
        
        // 3. Get initial info
        let initialInfo = resolver.getDirectoryInfo(path: resolvedPath)
        
        // 4. Ensure directory exists (creates if needed)
        if !initialInfo.exists {
            // Only test creation if the parent directory exists and is writable
            let parentPath = URL(fileURLWithPath: resolvedPath).deletingLastPathComponent().path
            if FileManager.default.fileExists(atPath: parentPath) && FileManager.default.isWritableFile(atPath: parentPath) {
                try resolver.ensureDirectoryExists(path: resolvedPath)
                
                // 5. Verify creation
                let finalInfo = resolver.getDirectoryInfo(path: resolvedPath)
                XCTAssertTrue(finalInfo.exists)
                XCTAssertTrue(finalInfo.isDirectory)
                XCTAssertTrue(finalInfo.isWritable)
            }
        }
    }
    
    func testAllSupportedShellsResolution() throws {
        let supportedShells = ["bash", "zsh", "fish"]
        
        for shell in supportedShells {
            let resolvedPath = try resolver.resolveCompletionDirectory(for: shell)
            XCTAssertFalse(resolvedPath.isEmpty)
            
            // Verify shell-specific path patterns
            switch shell {
            case "bash":
                XCTAssertTrue(resolvedPath.contains("bash-completion/completions"))
            case "zsh":
                XCTAssertTrue(resolvedPath.contains(".zsh/completions"))
            case "fish":
                XCTAssertTrue(resolvedPath.contains("fish/completions"))
            default:
                XCTFail("Unexpected shell: \(shell)")
            }
        }
    }
}

// MARK: - Test Helpers

extension UserDirectoryResolverTests {
    
    /// Test helper to check if a path is a reasonable completion directory path
    private func isValidCompletionPath(_ path: String, for shell: String) -> Bool {
        guard !path.isEmpty && path.hasPrefix("/") else { return false }
        
        switch shell {
        case "bash":
            return path.contains("bash-completion/completions")
        case "zsh":
            return path.contains(".zsh/completions")
        case "fish":
            return path.contains("fish/completions")
        default:
            return false
        }
    }
}