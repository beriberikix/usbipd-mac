// UserDirectoryResolver.swift
// Centralized user completion directory management for shell completions

import Foundation
import Common

/// Service that resolves and manages user completion directories for different shells
public class UserDirectoryResolver {
    
    /// Logger for directory resolution operations
    private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "user-directory-resolver")
    
    /// Initialize user directory resolver
    public init() {}
    
    /// Resolve completion directory path for the specified shell
    /// - Parameter shell: Shell type (bash, zsh, fish)
    /// - Returns: Directory path for shell completions
    /// - Throws: Directory resolution errors
    public func resolveCompletionDirectory(for shell: String) throws -> String {
        logger.debug("Resolving completion directory", context: ["shell": shell])
        
        switch shell.lowercased() {
        case "bash":
            return try resolveBashCompletionDirectory()
        case "zsh":
            return try resolveZshCompletionDirectory()
        case "fish":
            return try resolveFishCompletionDirectory()
        default:
            logger.error("Unsupported shell type", context: ["shell": shell])
            throw UserDirectoryResolverError.unsupportedShell("Unsupported shell type: \(shell)")
        }
    }
    
    /// Resolve bash completion directory following XDG Base Directory specification
    /// - Returns: Bash completion directory path
    /// - Throws: Directory resolution errors
    private func resolveBashCompletionDirectory() throws -> String {
        // Check XDG_DATA_HOME first (user-specific data directory)
        if let xdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"],
           !xdgDataHome.isEmpty {
            let completionDir = URL(fileURLWithPath: xdgDataHome)
                .appendingPathComponent("bash-completion")
                .appendingPathComponent("completions")
                .path
            logger.debug("Using XDG_DATA_HOME for bash completions", context: ["path": completionDir])
            return completionDir
        }
        
        // Fall back to ~/.local/share/bash-completion/completions
        guard let homeDirectory = ProcessInfo.processInfo.environment["HOME"],
              !homeDirectory.isEmpty else {
            throw UserDirectoryResolverError.environmentVariableNotFound("HOME environment variable not found or empty")
        }
        
        let completionDir = URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".local")
            .appendingPathComponent("share")
            .appendingPathComponent("bash-completion")
            .appendingPathComponent("completions")
            .path
        
        logger.debug("Using default bash completion directory", context: ["path": completionDir])
        return completionDir
    }
    
    /// Resolve zsh completion directory following zsh conventions
    /// - Returns: Zsh completion directory path
    /// - Throws: Directory resolution errors
    private func resolveZshCompletionDirectory() throws -> String {
        guard let homeDirectory = ProcessInfo.processInfo.environment["HOME"],
              !homeDirectory.isEmpty else {
            throw UserDirectoryResolverError.environmentVariableNotFound("HOME environment variable not found or empty")
        }
        
        // Use ~/.zsh/completions as the standard user completion directory
        let completionDir = URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".zsh")
            .appendingPathComponent("completions")
            .path
        
        logger.debug("Using zsh completion directory", context: ["path": completionDir])
        return completionDir
    }
    
    /// Resolve fish completion directory following fish shell conventions
    /// - Returns: Fish completion directory path
    /// - Throws: Directory resolution errors
    private func resolveFishCompletionDirectory() throws -> String {
        // Check XDG_CONFIG_HOME first
        if let xdgConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"],
           !xdgConfigHome.isEmpty {
            let completionDir = URL(fileURLWithPath: xdgConfigHome)
                .appendingPathComponent("fish")
                .appendingPathComponent("completions")
                .path
            logger.debug("Using XDG_CONFIG_HOME for fish completions", context: ["path": completionDir])
            return completionDir
        }
        
        // Fall back to ~/.config/fish/completions
        guard let homeDirectory = ProcessInfo.processInfo.environment["HOME"],
              !homeDirectory.isEmpty else {
            throw UserDirectoryResolverError.environmentVariableNotFound("HOME environment variable not found or empty")
        }
        
        let completionDir = URL(fileURLWithPath: homeDirectory)
            .appendingPathComponent(".config")
            .appendingPathComponent("fish")
            .appendingPathComponent("completions")
            .path
        
        logger.debug("Using default fish completion directory", context: ["path": completionDir])
        return completionDir
    }
    
    /// Validate that a directory path is acceptable for completion installation
    /// - Parameter path: Directory path to validate
    /// - Returns: True if directory is valid
    /// - Throws: Validation errors
    public func validateDirectory(path: String) throws -> Bool {
        logger.debug("Validating directory", context: ["path": path])
        
        // Check if path is empty
        guard !path.isEmpty else {
            throw UserDirectoryResolverError.invalidPath("Directory path cannot be empty")
        }
        
        // Check if path is too long (filesystem limits)
        guard path.count <= 1024 else {
            throw UserDirectoryResolverError.invalidPath("Directory path is too long (max 1024 characters)")
        }
        
        // Convert to URL for validation
        let directoryURL = URL(fileURLWithPath: path)
        
        // Check if parent directory exists and is accessible
        let parentURL = directoryURL.deletingLastPathComponent()
        let parentPath = parentURL.path
        
        // Skip parent validation if we're at filesystem root
        if parentPath != "/" && parentPath != directoryURL.path {
            guard FileManager.default.fileExists(atPath: parentPath) else {
                throw UserDirectoryResolverError.invalidPath("Parent directory does not exist: \(parentPath)")
            }
            
            guard FileManager.default.isWritableFile(atPath: parentPath) else {
                throw UserDirectoryResolverError.invalidPath("Parent directory is not writable: \(parentPath)")
            }
        }
        
        // If directory already exists, verify it's writable
        if FileManager.default.fileExists(atPath: path) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                throw UserDirectoryResolverError.invalidPath("Path exists but is not accessible: \(path)")
            }
            
            guard isDirectory.boolValue else {
                throw UserDirectoryResolverError.invalidPath("Path exists but is not a directory: \(path)")
            }
            
            guard FileManager.default.isWritableFile(atPath: path) else {
                throw UserDirectoryResolverError.invalidPath("Directory exists but is not writable: \(path)")
            }
        }
        
        logger.debug("Directory validation successful", context: ["path": path])
        return true
    }
    
    /// Create directory if it doesn't exist
    /// - Parameter path: Directory path to create
    /// - Throws: Directory creation errors
    public func createDirectory(path: String) throws {
        let directoryURL = URL(fileURLWithPath: path)
        
        if !FileManager.default.fileExists(atPath: path) {
            logger.debug("Creating directory", context: ["path": path])
            
            do {
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true,
                    attributes: [
                        .posixPermissions: 0o755 // rwxr-xr-x permissions
                    ]
                )
                
                logger.debug("Directory created successfully", context: ["path": path])
            } catch {
                logger.error("Failed to create directory", context: [
                    "path": path,
                    "error": error.localizedDescription
                ])
                throw UserDirectoryResolverError.directoryCreationFailed("Failed to create directory \(path): \(error.localizedDescription)")
            }
        } else {
            logger.debug("Directory already exists", context: ["path": path])
        }
    }
    
    /// Ensure directory exists and is valid for completion installation
    /// - Parameter path: Directory path to ensure
    /// - Throws: Directory validation or creation errors
    public func ensureDirectoryExists(path: String) throws {
        // First validate the path
        _ = try validateDirectory(path: path)
        
        // Then create if needed
        try createDirectory(path: path)
        
        logger.info("Directory ensured for completion installation", context: ["path": path])
    }
    
    /// Get directory information for diagnostics
    /// - Parameter path: Directory path to analyze
    /// - Returns: Directory information
    public func getDirectoryInfo(path: String) -> DirectoryInfo {
        var info = DirectoryInfo(path: path, exists: false, isDirectory: false, isWritable: false, size: nil, modificationDate: nil)
        
        if FileManager.default.fileExists(atPath: path) {
            info.exists = true
            
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
                info.isDirectory = isDirectory.boolValue
                info.isWritable = FileManager.default.isWritableFile(atPath: path)
                
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: path)
                    info.size = attributes[.size] as? Int64
                    info.modificationDate = attributes[.modificationDate] as? Date
                } catch {
                    logger.warning("Failed to get directory attributes", context: [
                        "path": path,
                        "error": error.localizedDescription
                    ])
                }
            }
        }
        
        return info
    }
}

// MARK: - Error Types

/// Errors that can occur during user directory resolution
public enum UserDirectoryResolverError: Error, LocalizedError {
    case unsupportedShell(String)
    case environmentVariableNotFound(String)
    case invalidPath(String)
    case directoryCreationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .unsupportedShell(let message):
            return "Unsupported shell: \(message)"
        case .environmentVariableNotFound(let message):
            return "Environment variable not found: \(message)"
        case .invalidPath(let message):
            return "Invalid directory path: \(message)"
        case .directoryCreationFailed(let message):
            return "Directory creation failed: \(message)"
        }
    }
}

// MARK: - Information Types

/// Information about a directory for diagnostics
public struct DirectoryInfo {
    public let path: String
    public var exists: Bool
    public var isDirectory: Bool
    public var isWritable: Bool
    public var size: Int64?
    public var modificationDate: Date?
    
    public init(path: String, exists: Bool, isDirectory: Bool, isWritable: Bool, size: Int64?, modificationDate: Date?) {
        self.path = path
        self.exists = exists
        self.isDirectory = isDirectory
        self.isWritable = isWritable
        self.size = size
        self.modificationDate = modificationDate
    }
}