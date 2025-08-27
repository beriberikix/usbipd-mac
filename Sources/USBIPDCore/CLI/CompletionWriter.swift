// CompletionWriter.swift
// Handles writing completion scripts to filesystem during build process

import Foundation
import Common

/// Service that writes generated completion scripts to the filesystem
public class CompletionWriter {
    
    /// Logger for completion writing operations
    private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "completion-writer")
    
    /// Available shell formatters
    private let formatters: [ShellCompletionFormatter]
    
    /// Initialize completion writer with shell formatters
    /// - Parameter formatters: Array of shell completion formatters
    public init(formatters: [ShellCompletionFormatter] = []) {
        self.formatters = formatters.isEmpty ? createDefaultFormatters() : formatters
    }
    
    /// Write completion scripts to the specified output directory
    /// - Parameters:
    ///   - data: Completion data to write
    ///   - outputDirectory: Directory path to write completion scripts
    /// - Throws: File writing errors
    public func writeCompletions(data: CompletionData, outputDirectory: String) throws {
        logger.debug("Starting completion script generation", context: [
            "outputDirectory": outputDirectory,
            "formattersCount": formatters.count
        ])
        
        // Validate output directory
        try validateOutputDirectory(path: outputDirectory)
        
        // Ensure output directory exists
        try createOutputDirectory(path: outputDirectory)
        
        var successCount = 0
        var errors: [String] = []
        
        // Generate completion scripts for each shell
        for formatter in formatters {
            do {
                try writeCompletionScript(data: data, formatter: formatter, outputDirectory: outputDirectory)
                successCount += 1
                logger.debug("Successfully wrote completion script", context: ["shell": formatter.shellType])
            } catch {
                let errorMessage = "Failed to write \(formatter.shellType) completion: \(error.localizedDescription)"
                errors.append(errorMessage)
                logger.error("Completion script write failed", context: [
                    "shell": formatter.shellType,
                    "error": error.localizedDescription
                ])
            }
        }
        
        // Report results
        logger.info("Completion script generation completed", context: [
            "successCount": successCount,
            "errorCount": errors.count,
            "outputDirectory": outputDirectory
        ])
        
        // If all scripts failed to write, throw an error
        if successCount == 0 && !errors.isEmpty {
            throw CompletionWriterError.allScriptsFailed(errors.joined(separator: "; "))
        }
        
        // If some scripts failed, log warnings but don't throw
        if !errors.isEmpty {
            logger.warning("Some completion scripts failed to write", context: [
                "errors": errors.joined(separator: "; ")
            ])
        }
    }
    
    /// Validate that the output directory path is acceptable
    /// - Parameter path: Directory path to validate
    /// - Returns: True if directory is valid
    /// - Throws: Validation errors
    public func validateOutputDirectory(path: String) throws -> Bool {
        logger.debug("Validating output directory", context: ["path": path])
        
        // Check if path is empty
        guard !path.isEmpty else {
            throw CompletionWriterError.invalidPath("Output directory path cannot be empty")
        }
        
        // Check if path is too long (filesystem limits)
        guard path.count <= 1024 else {
            throw CompletionWriterError.invalidPath("Output directory path is too long (max 1024 characters)")
        }
        
        // Convert to URL for validation
        let directoryURL = URL(fileURLWithPath: path)
        
        // Check if parent directory exists and is accessible
        let parentURL = directoryURL.deletingLastPathComponent()
        let parentPath = parentURL.path
        
        // Skip parent validation if we're at filesystem root
        if parentPath != "/" && parentPath != directoryURL.path {
            guard FileManager.default.fileExists(atPath: parentPath) else {
                throw CompletionWriterError.invalidPath("Parent directory does not exist: \(parentPath)")
            }
            
            guard FileManager.default.isWritableFile(atPath: parentPath) else {
                throw CompletionWriterError.invalidPath("Parent directory is not writable: \(parentPath)")
            }
        }
        
        // If directory already exists, verify it's writable
        if FileManager.default.fileExists(atPath: path) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                throw CompletionWriterError.invalidPath("Path exists but is not accessible: \(path)")
            }
            
            guard isDirectory.boolValue else {
                throw CompletionWriterError.invalidPath("Path exists but is not a directory: \(path)")
            }
            
            guard FileManager.default.isWritableFile(atPath: path) else {
                throw CompletionWriterError.invalidPath("Directory exists but is not writable: \(path)")
            }
        }
        
        logger.debug("Output directory validation successful", context: ["path": path])
        return true
    }
    
    /// Create output directory if it doesn't exist
    /// - Parameter path: Directory path to create
    /// - Throws: Directory creation errors
    private func createOutputDirectory(path: String) throws {
        let directoryURL = URL(fileURLWithPath: path)
        
        if !FileManager.default.fileExists(atPath: path) {
            logger.debug("Creating output directory", context: ["path": path])
            
            do {
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true,
                    attributes: [
                        .posixPermissions: 0o755 // rwxr-xr-x permissions
                    ]
                )
                
                logger.debug("Output directory created successfully", context: ["path": path])
            } catch {
                logger.error("Failed to create output directory", context: [
                    "path": path,
                    "error": error.localizedDescription
                ])
                throw CompletionWriterError.directoryCreationFailed("Failed to create directory \(path): \(error.localizedDescription)")
            }
        }
    }
    
    /// Write a single completion script using the specified formatter
    /// - Parameters:
    ///   - data: Completion data
    ///   - formatter: Shell completion formatter
    ///   - outputDirectory: Output directory path
    /// - Throws: Script writing errors
    private func writeCompletionScript(data: CompletionData, formatter: ShellCompletionFormatter, outputDirectory: String) throws {
        // Generate the completion script content
        let scriptContent = formatter.formatCompletion(data: data)
        
        // Validate the generated script
        let validationIssues = CompletionFormattingUtilities.validateCompletionScript(scriptContent, for: formatter.shellType)
        if !validationIssues.isEmpty {
            logger.warning("Completion script has validation issues", context: [
                "shell": formatter.shellType,
                "issues": validationIssues.joined(separator: "; ")
            ])
        }
        
        // Determine filename
        let filename = getCompletionFilename(for: formatter)
        let filePath = URL(fileURLWithPath: outputDirectory).appendingPathComponent(filename).path
        
        logger.debug("Writing completion script", context: [
            "shell": formatter.shellType,
            "filename": filename,
            "filePath": filePath,
            "contentLength": scriptContent.count
        ])
        
        do {
            // Write script content to file
            try scriptContent.write(
                toFile: filePath,
                atomically: true,
                encoding: .utf8
            )
            
            // Set appropriate file permissions (readable and executable)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644], // rw-r--r-- permissions
                ofItemAtPath: filePath
            )
            
            logger.info("Completion script written successfully", context: [
                "shell": formatter.shellType,
                "filePath": filePath,
                "size": scriptContent.count
            ])
            
        } catch {
            logger.error("Failed to write completion script", context: [
                "shell": formatter.shellType,
                "filePath": filePath,
                "error": error.localizedDescription
            ])
            throw CompletionWriterError.scriptWriteFailed("Failed to write \(formatter.shellType) completion script: \(error.localizedDescription)")
        }
    }
    
    /// Get appropriate filename for completion script
    /// - Parameter formatter: Shell completion formatter
    /// - Returns: Filename for the completion script
    private func getCompletionFilename(for formatter: ShellCompletionFormatter) -> String {
        switch formatter.shellType {
        case "bash":
            return "usbipd" // bash completions typically don't have extensions
        case "zsh":
            return "_usbipd" // zsh completions start with underscore
        case "fish":
            return "usbipd.fish" // fish completions have .fish extension
        default:
            // Fallback for unknown shell types
            let extension = formatter.fileExtension.isEmpty ? "" : ".\(formatter.fileExtension)"
            return "usbipd\(extension)"
        }
    }
    
    /// Create default shell formatters if none provided
    /// - Returns: Array of default shell completion formatters
    private func createDefaultFormatters() -> [ShellCompletionFormatter] {
        return [
            BashCompletionFormatter(),
            ZshCompletionFormatter(),
            FishCompletionFormatter()
        ]
    }
    
    /// Get completion scripts output summary
    /// - Parameter outputDirectory: Directory where scripts were written
    /// - Returns: Summary of written completion scripts
    public func getCompletionSummary(outputDirectory: String) -> CompletionWriteSummary {
        var scripts: [CompletionScriptInfo] = []
        
        for formatter in formatters {
            let filename = getCompletionFilename(for: formatter)
            let filePath = URL(fileURLWithPath: outputDirectory).appendingPathComponent(filename).path
            
            var scriptInfo = CompletionScriptInfo(
                shell: formatter.shellType,
                filename: filename,
                filePath: filePath,
                exists: false,
                size: 0,
                modificationDate: nil
            )
            
            if FileManager.default.fileExists(atPath: filePath) {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
                    scriptInfo.exists = true
                    scriptInfo.size = (attributes[.size] as? Int64) ?? 0
                    scriptInfo.modificationDate = attributes[.modificationDate] as? Date
                } catch {
                    logger.warning("Failed to get completion script attributes", context: [
                        "filePath": filePath,
                        "error": error.localizedDescription
                    ])
                }
            }
            
            scripts.append(scriptInfo)
        }
        
        return CompletionWriteSummary(
            outputDirectory: outputDirectory,
            scripts: scripts,
            totalScripts: scripts.count,
            successfulScripts: scripts.filter { $0.exists }.count
        )
    }
}

// MARK: - Error Types

/// Errors that can occur during completion writing
public enum CompletionWriterError: Error, LocalizedError {
    case invalidPath(String)
    case directoryCreationFailed(String)
    case scriptWriteFailed(String)
    case allScriptsFailed(String)
    case validationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidPath(let message):
            return "Invalid output path: \(message)"
        case .directoryCreationFailed(let message):
            return "Directory creation failed: \(message)"
        case .scriptWriteFailed(let message):
            return "Script write failed: \(message)"
        case .allScriptsFailed(let message):
            return "All completion scripts failed: \(message)"
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        }
    }
}

// MARK: - Summary Types

/// Information about a written completion script
public struct CompletionScriptInfo {
    public let shell: String
    public let filename: String
    public let filePath: String
    public var exists: Bool
    public var size: Int64
    public var modificationDate: Date?
    
    public init(shell: String, filename: String, filePath: String, exists: Bool, size: Int64, modificationDate: Date?) {
        self.shell = shell
        self.filename = filename
        self.filePath = filePath
        self.exists = exists
        self.size = size
        self.modificationDate = modificationDate
    }
}

/// Summary of completion writing operation
public struct CompletionWriteSummary {
    public let outputDirectory: String
    public let scripts: [CompletionScriptInfo]
    public let totalScripts: Int
    public let successfulScripts: Int
    
    public var allScriptsSuccessful: Bool {
        return successfulScripts == totalScripts
    }
    
    public var hasFailures: Bool {
        return successfulScripts < totalScripts
    }
    
    public init(outputDirectory: String, scripts: [CompletionScriptInfo], totalScripts: Int, successfulScripts: Int) {
        self.outputDirectory = outputDirectory
        self.scripts = scripts
        self.totalScripts = totalScripts
        self.successfulScripts = successfulScripts
    }
}