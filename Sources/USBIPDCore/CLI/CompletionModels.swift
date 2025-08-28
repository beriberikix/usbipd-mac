// CompletionModels.swift
// Data models for shell completion generation

import Foundation

/// Unified data structure representing completion information
public struct CompletionData: Codable, Sendable {
    public let commands: [CompletionCommand]
    public let globalOptions: [CompletionOption]
    public let dynamicProviders: [DynamicValueProvider]
    public let metadata: CompletionMetadata
    
    public init(
        commands: [CompletionCommand],
        globalOptions: [CompletionOption],
        dynamicProviders: [DynamicValueProvider],
        metadata: CompletionMetadata
    ) {
        self.commands = commands
        self.globalOptions = globalOptions
        self.dynamicProviders = dynamicProviders
        self.metadata = metadata
    }
}

/// Represents a command or subcommand for completion
public struct CompletionCommand: Codable, Sendable {
    public let name: String
    public let description: String
    public let options: [CompletionOption]
    public let arguments: [CompletionArgument]
    public let subcommands: [CompletionCommand]
    
    public init(
        name: String,
        description: String,
        options: [CompletionOption] = [],
        arguments: [CompletionArgument] = [],
        subcommands: [CompletionCommand] = []
    ) {
        self.name = name
        self.description = description
        self.options = options
        self.arguments = arguments
        self.subcommands = subcommands
    }
}

/// Represents a command-line option for completion
public struct CompletionOption: Codable, Sendable {
    public let short: String?
    public let long: String
    public let description: String
    public let takesValue: Bool
    public let valueType: CompletionValueType
    
    public init(
        short: String? = nil,
        long: String,
        description: String,
        takesValue: Bool = false,
        valueType: CompletionValueType = .none
    ) {
        self.short = short
        self.long = long
        self.description = description
        self.takesValue = takesValue
        self.valueType = valueType
    }
}

/// Represents a command argument for completion
public struct CompletionArgument: Codable, Sendable {
    public let name: String
    public let description: String
    public let required: Bool
    public let valueType: CompletionValueType
    
    public init(
        name: String,
        description: String,
        required: Bool = true,
        valueType: CompletionValueType = .string
    ) {
        self.name = name
        self.description = description
        self.required = required
        self.valueType = valueType
    }
}

/// Represents different types of values for completion
public enum CompletionValueType: String, Codable, Sendable {
    case none
    case string
    case file
    case directory
    case deviceID = "device-id"
    case ipAddress = "ip-address"
    case port
    case busID = "bus-id"
}

/// Provides dynamic completion values for specific contexts
public struct DynamicValueProvider: Codable, Sendable {
    public let context: String
    public let command: String
    public let fallback: [String]
    
    public init(
        context: String,
        command: String,
        fallback: [String] = []
    ) {
        self.context = context
        self.command = command
        self.fallback = fallback
    }
}

/// Metadata about the completion data
public struct CompletionMetadata: Codable, Sendable {
    public let version: String
    public let generatedAt: Date
    public let supportedShells: [String]
    
    public init(
        version: String,
        generatedAt: Date = Date(),
        supportedShells: [String] = ["bash", "zsh", "fish"]
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.supportedShells = supportedShells
    }
}

// MARK: - Installation Models

/// Summary of completion installation operation
public struct CompletionInstallSummary: Codable, Sendable {
    public let shells: [CompletionShellStatus]
    public let successful: Bool
    public let errors: [String]
    public let installedFiles: [CompletionFileInfo]
    
    public init(
        shells: [CompletionShellStatus],
        successful: Bool,
        errors: [String] = [],
        installedFiles: [CompletionFileInfo] = []
    ) {
        self.shells = shells
        self.successful = successful
        self.errors = errors
        self.installedFiles = installedFiles
    }
}

/// Summary of completion uninstallation operation
public struct CompletionUninstallSummary: Codable, Sendable {
    public let shells: [CompletionShellStatus]
    public let successful: Bool
    public let errors: [String]
    public let removedFiles: [CompletionFileInfo]
    
    public init(
        shells: [CompletionShellStatus],
        successful: Bool,
        errors: [String] = [],
        removedFiles: [CompletionFileInfo] = []
    ) {
        self.shells = shells
        self.successful = successful
        self.errors = errors
        self.removedFiles = removedFiles
    }
}

/// Summary of completion status check operation
public struct CompletionStatusSummary: Codable, Sendable {
    public let shells: [CompletionShellStatus]
    public let overallInstalled: Bool
    public let needsUpdate: Bool
    public let errors: [String]
    
    public init(
        shells: [CompletionShellStatus],
        overallInstalled: Bool,
        needsUpdate: Bool,
        errors: [String] = []
    ) {
        self.shells = shells
        self.overallInstalled = overallInstalled
        self.needsUpdate = needsUpdate
        self.errors = errors
    }
}

/// Information about a completion file
public struct CompletionFileInfo: Codable, Sendable {
    public let path: String
    public let shell: String
    public let exists: Bool
    public let upToDate: Bool
    public let size: Int64?
    public let modificationDate: Date?
    
    public init(
        path: String,
        shell: String,
        exists: Bool,
        upToDate: Bool,
        size: Int64? = nil,
        modificationDate: Date? = nil
    ) {
        self.path = path
        self.shell = shell
        self.exists = exists
        self.upToDate = upToDate
        self.size = size
        self.modificationDate = modificationDate
    }
}

/// Status of completion installation for a specific shell
public struct CompletionShellStatus: Codable, Sendable {
    public let shell: String
    public let installed: Bool
    public let upToDate: Bool
    public let completionFile: CompletionFileInfo?
    public let error: String?
    
    public init(
        shell: String,
        installed: Bool,
        upToDate: Bool,
        completionFile: CompletionFileInfo? = nil,
        error: String? = nil
    ) {
        self.shell = shell
        self.installed = installed
        self.upToDate = upToDate
        self.completionFile = completionFile
        self.error = error
    }
}