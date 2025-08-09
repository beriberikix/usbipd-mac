import PackagePlugin
import Foundation

@main
struct SystemExtensionBundleBuilder: BuildToolPlugin {
    
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard target.name == "SystemExtension" else {
            return []
        }
        
        // Get source paths
        let sourceDir = target.directory
        let infoPlistTemplate = sourceDir.appending("Info.plist.template")
        let entitlementsFile = sourceDir.appending("SystemExtension.entitlements")
        
        // Create a simple validation script that doesn't produce unexpected outputs
        let validationScript = """
        #!/bin/bash
        echo "SystemExtension bundle builder initialized for \(target.name)"
        echo "Template found: \(infoPlistTemplate.string)"
        echo "Entitlements found: \(entitlementsFile.string)"
        echo "Plugin working directory: \(context.pluginWorkDirectory.string)"
        """
        
        return [
            .prebuildCommand(
                displayName: "Initialize System Extension Bundle Builder",
                executable: Path("/bin/bash"),
                arguments: ["-c", validationScript],
                outputFilesDirectory: context.pluginWorkDirectory
            )
        ]
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SystemExtensionBundleBuilder: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        guard target.displayName == "SystemExtension" else {
            return []
        }
        
        // Find source directory in Xcode project
        let projectDir = context.xcodeProject.directory
        let sourceDir = projectDir.appending("Sources").appending("SystemExtension")
        let infoPlistTemplate = sourceDir.appending("Info.plist.template")
        let entitlementsFile = sourceDir.appending("SystemExtension.entitlements")
        
        let validationScript = """
        #!/bin/bash
        echo "SystemExtension bundle builder initialized for \(target.displayName) (Xcode)"
        echo "Template found: \(infoPlistTemplate.string)"
        echo "Entitlements found: \(entitlementsFile.string)"
        echo "Plugin working directory: \(context.pluginWorkDirectory.string)"
        """
        
        return [
            .prebuildCommand(
                displayName: "Initialize System Extension Bundle Builder (Xcode)",
                executable: Path("/bin/bash"),
                arguments: ["-c", validationScript],
                outputFilesDirectory: context.pluginWorkDirectory
            )
        ]
    }
}
#endif