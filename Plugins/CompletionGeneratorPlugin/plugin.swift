// plugin.swift
// Swift Package Manager build tool plugin for generating shell completion scripts

import PackagePlugin

@main
struct CompletionGeneratorPlugin: BuildToolPlugin {
    
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        // Only generate completions for the main CLI executable
        guard target.name == "USBIPDCLI" else {
            return []
        }
        
        // Create output directory for completion scripts
        let outputDirectory = context.pluginWorkDirectory.appending("completions")
        
        // Generate completion scripts for all supported shells
        let completionCommand = Command.buildCommand(
            displayName: "Generate Shell Completion Scripts",
            executable: target.directory.appending("generate-completions.sh"),
            arguments: [
                outputDirectory.string
            ],
            environment: [
                "PLUGIN_WORK_DIR": context.pluginWorkDirectory.string,
                "TARGET_DIR": target.directory.string,
                "PACKAGE_DIR": context.package.directory.string
            ],
            inputFiles: [
                target.directory.appending("CommandLineParser.swift"),
                target.directory.appending("Commands.swift"),
                target.directory.appending("CompletionCommand.swift"),
            ],
            outputFiles: [
                outputDirectory.appending("usbipd"),         // bash
                outputDirectory.appending("_usbipd"),        // zsh  
                outputDirectory.appending("usbipd.fish")     // fish
            ]
        )
        
        return [completionCommand]
    }
}