import PackagePlugin
import Foundation

@main
struct SystemExtensionBundleBuilder: BuildToolPlugin {
    
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard target.name == "SystemExtension" else {
            return []
        }
        
        let bundleBuilder = BundleBuilder(context: context, target: target)
        return try bundleBuilder.createBundle()
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SystemExtensionBundleBuilder: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        guard target.displayName == "SystemExtension" else {
            return []
        }
        
        let bundleBuilder = XcodeBundleBuilder(context: context, target: target)
        return try bundleBuilder.createBundle()
    }
}
#endif