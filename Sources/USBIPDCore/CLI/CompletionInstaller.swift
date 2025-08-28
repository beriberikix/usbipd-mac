// CompletionInstaller.swift
// Core service for installing, uninstalling, and managing shell completion files

import Foundation
import Common

/// Service that manages installation of completion files to user directories
public class CompletionInstaller {
    
    /// Logger for completion installation operations
    private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "completion-installer")
    
    /// Directory resolver for shell completion paths
    private let directoryResolver: UserDirectoryResolver
    
    /// Completion writer for generating completion files
    private let completionWriter: CompletionWriter
    
    /// Initialize completion installer with dependencies
    /// - Parameters:
    ///   - directoryResolver: Service to resolve user completion directories
    ///   - completionWriter: Service to write completion files
    public init(directoryResolver: UserDirectoryResolver = UserDirectoryResolver(), 
                completionWriter: CompletionWriter = CompletionWriter()) {
        self.directoryResolver = directoryResolver
        self.completionWriter = completionWriter
    }
    
    /// Install completion files for the specified shell
    /// - Parameters:
    ///   - data: Completion data to install
    ///   - shell: Target shell (bash, zsh, fish)
    /// - Returns: Installation result with status and details
    /// - Throws: Installation errors
    @discardableResult
    public func install(data: CompletionData, for shell: String) throws -> CompletionInstallationResult {
        logger.info("Starting completion installation", context: ["shell": shell])
        
        let startTime = Date()
        var rollbackActions: [() throws -> Void] = []
        
        do {
            // Resolve target directory for shell
            let targetDirectory = try directoryResolver.resolveCompletionDirectory(for: shell)
            logger.debug("Target directory resolved", context: ["directory": targetDirectory])
            
            // Validate and ensure target directory exists
            try directoryResolver.ensureDirectoryExists(path: targetDirectory)
            rollbackActions.append {
                // Note: We don't remove created directories in rollback to avoid affecting other completions
                self.logger.debug("Rollback: Directory creation cannot be safely reverted", context: ["directory": targetDirectory])
            }
            
            // Create temporary directory for completion generation
            let tempDirectory = try createTemporaryDirectory()
            rollbackActions.append {
                try? self.cleanupTemporaryDirectory(path: tempDirectory)
            }
            
            // Generate completion files in temporary directory
            try completionWriter.writeCompletions(data: data, outputDirectory: tempDirectory)
            
            // Get the specific completion file for this shell
            let completionFilename = getCompletionFilename(for: shell)
            let sourcePath = URL(fileURLWithPath: tempDirectory).appendingPathComponent(completionFilename).path
            let targetPath = URL(fileURLWithPath: targetDirectory).appendingPathComponent(completionFilename).path
            
            // Backup existing completion file if it exists
            var backupPath: String?
            if FileManager.default.fileExists(atPath: targetPath) {
                backupPath = try createBackup(of: targetPath)
                rollbackActions.append {
                    try? self.restoreBackup(from: backupPath!, to: targetPath)
                }
            }
            
            // Install the completion file
            try installCompletionFile(from: sourcePath, to: targetPath)
            rollbackActions.append {
                try? FileManager.default.removeItem(atPath: targetPath)
            }
            
            // Cleanup temporary directory
            try cleanupTemporaryDirectory(path: tempDirectory)
            
            let duration = Date().timeIntervalSince(startTime)
            logger.info("Completion installation completed successfully", context: [
                "shell": shell,
                "targetPath": targetPath,
                "duration": String(format: "%.2f", duration)
            ])
            
            return CompletionInstallationResult(
                success: true,
                shell: shell,
                targetPath: targetPath,
                backupPath: backupPath,
                duration: duration,
                error: nil
            )
        } catch {
            logger.error("Completion installation failed, performing rollback", context: [
                "shell": shell,
                "error": error.localizedDescription
            ])
            
            // Execute rollback actions in reverse order
            for rollbackAction in rollbackActions.reversed() {
                do {
                    try rollbackAction()
                } catch {
                    logger.warning("Rollback action failed", context: ["error": error.localizedDescription])
                }
            }
            
            let duration = Date().timeIntervalSince(startTime)
            return CompletionInstallationResult(
                success: false,
                shell: shell,
                targetPath: nil,
                backupPath: nil,
                duration: duration,
                error: error
            )
        }
    }
    
    /// Uninstall completion files for the specified shell
    /// - Parameter shell: Target shell to remove completions from
    /// - Returns: Uninstallation result with status and details
    /// - Throws: Uninstallation errors
    @discardableResult
    public func uninstall(for shell: String) throws -> UninstallationResult {
        logger.info("Starting completion uninstallation", context: ["shell": shell])
        
        let startTime = Date()
        
        do {
            // Resolve target directory for shell
            let targetDirectory = try directoryResolver.resolveCompletionDirectory(for: shell)
            let completionFilename = getCompletionFilename(for: shell)
            let targetPath = URL(fileURLWithPath: targetDirectory).appendingPathComponent(completionFilename).path
            
            // Check if completion file exists
            guard FileManager.default.fileExists(atPath: targetPath) else {
                let duration = Date().timeIntervalSince(startTime)
                logger.info("Completion file does not exist, nothing to uninstall", context: [
                    "shell": shell,
                    "targetPath": targetPath
                ])
                
                return UninstallationResult(
                    success: true,
                    shell: shell,
                    removedPath: nil,
                    duration: duration,
                    error: nil
                )
            }
            
            // Create backup before removal
            let backupPath = try createBackup(of: targetPath)
            
            // Remove completion file
            try FileManager.default.removeItem(atPath: targetPath)
            
            let duration = Date().timeIntervalSince(startTime)
            logger.info("Completion uninstallation completed successfully", context: [
                "shell": shell,
                "removedPath": targetPath,
                "backupPath": backupPath,
                "duration": String(format: "%.2f", duration)
            ])
            
            return UninstallationResult(
                success: true,
                shell: shell,
                removedPath: targetPath,
                duration: duration,
                error: nil
            )
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            logger.error("Completion uninstallation failed", context: [
                "shell": shell,
                "error": error.localizedDescription
            ])
            
            return UninstallationResult(
                success: false,
                shell: shell,
                removedPath: nil,
                duration: duration,
                error: error
            )
        }
    }
    
    /// Get installation status for the specified shell
    /// - Parameter shell: Target shell to check
    /// - Returns: Installation status information
    public func getInstallationStatus(for shell: String) -> InstallationStatus {
        logger.debug("Checking installation status", context: ["shell": shell])
        
        do {
            // Resolve target directory for shell
            let targetDirectory = try directoryResolver.resolveCompletionDirectory(for: shell)
            let completionFilename = getCompletionFilename(for: shell)
            let targetPath = URL(fileURLWithPath: targetDirectory).appendingPathComponent(completionFilename).path
            
            // Get directory information
            let directoryInfo = directoryResolver.getDirectoryInfo(path: targetDirectory)
            
            // Check if completion file exists
            var fileInfo: FileInfo?
            if FileManager.default.fileExists(atPath: targetPath) {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: targetPath)
                    fileInfo = FileInfo(
                        path: targetPath,
                        exists: true,
                        size: (attributes[.size] as? Int64) ?? 0,
                        modificationDate: attributes[.modificationDate] as? Date,
                        permissions: attributes[.posixPermissions] as? NSNumber
                    )
                } catch {
                    logger.warning("Failed to get completion file attributes", context: [
                        "targetPath": targetPath,
                        "error": error.localizedDescription
                    ])
                }
            }
            
            let isInstalled = fileInfo?.exists ?? false
            
            return InstallationStatus(
                shell: shell,
                isInstalled: isInstalled,
                targetDirectory: targetDirectory,
                targetPath: targetPath,
                directoryInfo: directoryInfo,
                fileInfo: fileInfo,
                error: nil
            )
        } catch {
            logger.error("Failed to check installation status", context: [
                "shell": shell,
                "error": error.localizedDescription
            ])
            
            return InstallationStatus(
                shell: shell,
                isInstalled: false,
                targetDirectory: nil,
                targetPath: nil,
                directoryInfo: nil,
                fileInfo: nil,
                error: error
            )
        }
    }
    
    /// Install completion files for all supported shells
    /// - Parameter data: Completion data to install
    /// - Returns: Array of installation results for each shell
    public func installAll(data: CompletionData) -> [CompletionInstallationResult] {
        let supportedShells = ["bash", "zsh", "fish"]
        var results: [CompletionInstallationResult] = []
        
        logger.info("Starting installation for all supported shells", context: ["shellCount": supportedShells.count])
        
        for shell in supportedShells {
            do {
                let result = try install(data: data, for: shell)
                results.append(result)
            } catch {
                let result = CompletionInstallationResult(
                    success: false,
                    shell: shell,
                    targetPath: nil,
                    backupPath: nil,
                    duration: 0.0,
                    error: error
                )
                results.append(result)
            }
        }
        
        let successCount = results.filter { $0.success }.count
        logger.info("Installation for all shells completed", context: [
            "totalShells": supportedShells.count,
            "successCount": successCount,
            "failureCount": supportedShells.count - successCount
        ])
        
        return results
    }
    
    /// Uninstall completion files from all supported shells
    /// - Returns: Array of uninstallation results for each shell
    public func uninstallAll() -> [UninstallationResult] {
        let supportedShells = ["bash", "zsh", "fish"]
        var results: [UninstallationResult] = []
        
        logger.info("Starting uninstallation for all supported shells", context: ["shellCount": supportedShells.count])
        
        for shell in supportedShells {
            do {
                let result = try uninstall(for: shell)
                results.append(result)
            } catch {
                let result = UninstallationResult(
                    success: false,
                    shell: shell,
                    removedPath: nil,
                    duration: 0.0,
                    error: error
                )
                results.append(result)
            }
        }
        
        let successCount = results.filter { $0.success }.count
        logger.info("Uninstallation for all shells completed", context: [
            "totalShells": supportedShells.count,
            "successCount": successCount,
            "failureCount": supportedShells.count - successCount
        ])
        
        return results
    }
    
    /// Get installation status for all supported shells
    /// - Returns: Array of installation statuses for each shell
    public func getStatusAll() -> [InstallationStatus] {
        let supportedShells = ["bash", "zsh", "fish"]
        return supportedShells.map { shell in
            getInstallationStatus(for: shell)
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// Get appropriate filename for completion file based on shell
    /// - Parameter shell: Shell type
    /// - Returns: Completion filename
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
    
    /// Create a temporary directory for completion file generation
    /// - Returns: Temporary directory path
    /// - Throws: Directory creation errors
    private func createTemporaryDirectory() throws -> String {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("usbipd-completions")
            .appendingPathComponent(UUID().uuidString)
        
        try FileManager.default.createDirectory(
            at: tempURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700] // rwx------ permissions
        )
        
        return tempURL.path
    }
    
    /// Clean up temporary directory
    /// - Parameter path: Temporary directory path to remove
    /// - Throws: Cleanup errors
    private func cleanupTemporaryDirectory(path: String) throws {
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
            logger.debug("Temporary directory cleaned up", context: ["path": path])
        }
    }
    
    /// Create backup of existing completion file
    /// - Parameter filePath: Path to file to backup
    /// - Returns: Backup file path
    /// - Throws: Backup creation errors
    private func createBackup(of filePath: String) throws -> String {
        let backupPath = filePath + ".backup-" + String(Int(Date().timeIntervalSince1970))
        try FileManager.default.copyItem(atPath: filePath, toPath: backupPath)
        logger.debug("Backup created", context: ["original": filePath, "backup": backupPath])
        return backupPath
    }
    
    /// Restore backup file
    /// - Parameters:
    ///   - backupPath: Path to backup file
    ///   - originalPath: Path to restore backup to
    /// - Throws: Restore errors
    private func restoreBackup(from backupPath: String, to originalPath: String) throws {
        if FileManager.default.fileExists(atPath: backupPath) {
            // Remove current file if it exists
            if FileManager.default.fileExists(atPath: originalPath) {
                try FileManager.default.removeItem(atPath: originalPath)
            }
            
            // Restore from backup
            try FileManager.default.moveItem(atPath: backupPath, toPath: originalPath)
            logger.debug("Backup restored", context: ["backup": backupPath, "original": originalPath])
        }
    }
    
    /// Install completion file from source to target
    /// - Parameters:
    ///   - sourcePath: Source completion file path
    ///   - targetPath: Target installation path
    /// - Throws: Installation errors
    private func installCompletionFile(from sourcePath: String, to targetPath: String) throws {
        try FileManager.default.copyItem(atPath: sourcePath, toPath: targetPath)
        
        // Set appropriate permissions
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], // rw-r--r-- permissions
            ofItemAtPath: targetPath
        )
        
        logger.debug("Completion file installed", context: ["source": sourcePath, "target": targetPath])
    }
}

// MARK: - Result Types

/// Result of a completion installation operation
public struct CompletionInstallationResult {
    public let success: Bool
    public let shell: String
    public let targetPath: String?
    public let backupPath: String?
    public let duration: TimeInterval
    public let error: Error?
    
    public init(success: Bool, shell: String, targetPath: String?, backupPath: String?, duration: TimeInterval, error: Error?) {
        self.success = success
        self.shell = shell
        self.targetPath = targetPath
        self.backupPath = backupPath
        self.duration = duration
        self.error = error
    }
}

/// Result of a completion uninstallation operation
public struct UninstallationResult {
    public let success: Bool
    public let shell: String
    public let removedPath: String?
    public let duration: TimeInterval
    public let error: Error?
    
    public init(success: Bool, shell: String, removedPath: String?, duration: TimeInterval, error: Error?) {
        self.success = success
        self.shell = shell
        self.removedPath = removedPath
        self.duration = duration
        self.error = error
    }
}

/// Status of completion installation for a shell
public struct InstallationStatus {
    public let shell: String
    public let isInstalled: Bool
    public let targetDirectory: String?
    public let targetPath: String?
    public let directoryInfo: DirectoryInfo?
    public let fileInfo: FileInfo?
    public let error: Error?
    
    public init(shell: String, isInstalled: Bool, targetDirectory: String?, targetPath: String?, directoryInfo: DirectoryInfo?, fileInfo: FileInfo?, error: Error?) {
        self.shell = shell
        self.isInstalled = isInstalled
        self.targetDirectory = targetDirectory
        self.targetPath = targetPath
        self.directoryInfo = directoryInfo
        self.fileInfo = fileInfo
        self.error = error
    }
}

/// Information about a file for diagnostics
public struct FileInfo {
    public let path: String
    public let exists: Bool
    public let size: Int64
    public let modificationDate: Date?
    public let permissions: NSNumber?
    
    public init(path: String, exists: Bool, size: Int64, modificationDate: Date?, permissions: NSNumber?) {
        self.path = path
        self.exists = exists
        self.size = size
        self.modificationDate = modificationDate
        self.permissions = permissions
    }
}