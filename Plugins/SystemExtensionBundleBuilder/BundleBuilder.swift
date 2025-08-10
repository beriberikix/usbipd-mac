import Foundation
import PackagePlugin

/// Handles the complete creation of System Extension bundles
struct BundleBuilder {
    let context: PluginContext
    let target: Target
    let bundleName: String
    
    init(context: PluginContext, target: Target, bundleName: String = "SystemExtension.systemextension") {
        self.context = context
        self.target = target
        self.bundleName = bundleName
    }
    
    /// Creates the complete System Extension bundle
    func createBundle() throws -> [Command] {
        let outputDir = context.pluginWorkDirectory.appending("bundles")
        let bundlePath = outputDir.appending(bundleName)
        
        // Get source paths
        let sourceDir = target.directory
        let infoPlistTemplate = sourceDir.appending("Info.plist.template")
        let entitlementsFile = sourceDir.appending("SystemExtension.entitlements")
        
        // Create bundle structure paths
        let contentsDir = bundlePath.appending("Contents")
        let macOSDir = contentsDir.appending("MacOS")
        let resourcesDir = contentsDir.appending("Resources")
        let infoPlist = contentsDir.appending("Info.plist")
        
        // Generate template variables
        let templateVars = generateTemplateVariables()
        
        // Create the bundle creation script
        let bundleScript = createBundleScript(
            bundlePath: bundlePath,
            infoPlistTemplate: infoPlistTemplate,
            entitlementsFile: entitlementsFile,
            infoPlist: infoPlist,
            macOSDir: macOSDir,
            resourcesDir: resourcesDir,
            templateVars: templateVars
        )
        
        return [
            .prebuildCommand(
                displayName: "Create System Extension Bundle",
                executable: Path("/bin/bash"),
                arguments: ["-c", bundleScript],
                outputFilesDirectory: outputDir
            )
        ]
    }
    
    /// Generates template variables for Info.plist processing
    private func generateTemplateVariables() -> [String: String] {
        return [
            "BUNDLE_DISPLAY_NAME": "USB\\/IP System Extension",
            "EXECUTABLE_NAME": "SystemExtension",
            "BUNDLE_IDENTIFIER": "com.github.usbipd-mac.SystemExtension",
            "BUNDLE_NAME": "SystemExtension",
            "VERSION_STRING": "1.0.0",
            "BUILD_VERSION": "1",
            "MINIMUM_SYSTEM_VERSION": "11.0",
            "PRINCIPAL_CLASS": "SystemExtensionManager",
            "COPYRIGHT_STRING": "Copyright © 2024 usbipd-mac contributors",
            "USAGE_DESCRIPTION": "USB\\/IP System Extension for sharing USB devices over IP networks",
            "EXTENSION_NAME": "USBIPSystemExtension",
            "USB_INTERFACE_CLASS": "9", // Hub class - generic USB device matching
            "USB_VENDOR_ID": "0" // Match any vendor for development
        ]
    }
    
    /// Creates the bash script that handles bundle creation
    private func createBundleScript(
        bundlePath: Path,
        infoPlistTemplate: Path,
        entitlementsFile: Path,
        infoPlist: Path,
        macOSDir: Path,
        resourcesDir: Path,
        templateVars: [String: String]
    ) -> String {
        
        // Create template substitution commands
        var substitutionCommands: [String] = []
        for (key, value) in templateVars {
            substitutionCommands.append("sed -i '' 's/{{\(key)}}/\(value)/g' \"\(infoPlist.string)\"")
        }
        
        let script = """
        #!/bin/bash
        set -e
        
        echo "Creating System Extension bundle at \(bundlePath.string)"
        
        # Create bundle directory structure
        mkdir -p "\(bundlePath.string)"
        mkdir -p "\(bundlePath.string)/Contents/MacOS"
        mkdir -p "\(bundlePath.string)/Contents/Resources"
        
        echo "Bundle directory structure created"
        
        # Copy and process Info.plist template
        if [ -f "\(infoPlistTemplate.string)" ]; then
            cp "\(infoPlistTemplate.string)" "\(infoPlist.string)"
            echo "Info.plist template copied"
            
            # Apply template substitutions
        \(substitutionCommands.joined(separator: "\n    "))
            echo "Template variables substituted"
        else
            echo "Warning: Info.plist template not found at \(infoPlistTemplate.string)"
        fi
        
        # Copy entitlements to Resources
        if [ -f "\(entitlementsFile.string)" ]; then
            cp "\(entitlementsFile.string)" "\(resourcesDir.string)/SystemExtension.entitlements"
            echo "Entitlements copied to bundle"
        else
            echo "Warning: Entitlements file not found at \(entitlementsFile.string)"
        fi
        
        # Note: Executable will be copied by post-build step
        # This is a placeholder for the executable location
        touch "\(macOSDir.string)/SystemExtension"
        echo "Executable placeholder created"
        
        echo "System Extension bundle creation completed"
        echo "Bundle location: \(bundlePath.string)"
        
        # Set proper permissions
        chmod -R 755 "\(bundlePath.string)"
        echo "Bundle permissions set"
        
        # Code signing
        \(createCodeSigningCommands(bundlePath: bundlePath, executablePath: macOSDir.appending("SystemExtension"), entitlementsPath: entitlementsFile.string).joined(separator: "\n"))
        
        # Development mode support
        \(createDevelopmentModeCommands().joined(separator: "\n"))
        """
        
        return script
    }
    
    /// Creates code signing commands for the bundle
    private func createCodeSigningCommands(bundlePath: Path, executablePath: Path, entitlementsPath: String) -> [String] {
        let signingConfig = CodeSigning.Configuration(
            certificateIdentity: nil, // Auto-detect
            developmentMode: true,
            signBundle: true,
            entitlementsPath: entitlementsPath
        )
        
        let codeSigning = CodeSigning(configuration: signingConfig)
        return codeSigning.createSigningCommands(bundlePath: bundlePath, executablePath: executablePath)
    }
    
    /// Creates development mode support commands
    private func createDevelopmentModeCommands() -> [String] {
        let signingConfig = CodeSigning.Configuration(
            developmentMode: true,
            entitlementsPath: ""
        )
        
        let codeSigning = CodeSigning(configuration: signingConfig)
        return codeSigning.createDevelopmentModeCommands()
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

/// Xcode-specific bundle builder
struct XcodeBundleBuilder {
    let context: XcodePluginContext
    let target: XcodeTarget
    let bundleName: String
    
    init(context: XcodePluginContext, target: XcodeTarget, bundleName: String = "SystemExtension.systemextension") {
        self.context = context
        self.target = target
        self.bundleName = bundleName
    }
    
    /// Creates the complete System Extension bundle for Xcode builds
    func createBundle() throws -> [Command] {
        let outputDir = context.pluginWorkDirectory.appending("bundles")
        let bundlePath = outputDir.appending(bundleName)
        
        // Find source directory in Xcode project
        let projectDir = context.xcodeProject.directory
        let sourceDir = projectDir.appending("Sources").appending("SystemExtension")
        let infoPlistTemplate = sourceDir.appending("Info.plist.template")
        let entitlementsFile = sourceDir.appending("SystemExtension.entitlements")
        
        // Create bundle structure paths
        let contentsDir = bundlePath.appending("Contents")
        let macOSDir = contentsDir.appending("MacOS")
        let resourcesDir = contentsDir.appending("Resources")
        let infoPlist = contentsDir.appending("Info.plist")
        
        // Generate template variables (same as SPM version)
        let templateVars = generateXcodeTemplateVariables()
        
        // Create the bundle creation script
        let bundleScript = createXcodeBundleScript(
            bundlePath: bundlePath,
            infoPlistTemplate: infoPlistTemplate,
            entitlementsFile: entitlementsFile,
            infoPlist: infoPlist,
            macOSDir: macOSDir,
            resourcesDir: resourcesDir,
            templateVars: templateVars
        )
        
        return [
            .prebuildCommand(
                displayName: "Create System Extension Bundle (Xcode)",
                executable: Path("/bin/bash"),
                arguments: ["-c", bundleScript],
                outputFilesDirectory: outputDir
            )
        ]
    }
    
    /// Generates template variables for Xcode Info.plist processing
    private func generateXcodeTemplateVariables() -> [String: String] {
        return [
            "BUNDLE_DISPLAY_NAME": "USB\\/IP System Extension",
            "EXECUTABLE_NAME": "SystemExtension",
            "BUNDLE_IDENTIFIER": "com.github.usbipd-mac.SystemExtension",
            "BUNDLE_NAME": "SystemExtension",
            "VERSION_STRING": "1.0.0",
            "BUILD_VERSION": "1",
            "MINIMUM_SYSTEM_VERSION": "11.0",
            "PRINCIPAL_CLASS": "SystemExtensionManager",
            "COPYRIGHT_STRING": "Copyright © 2024 usbipd-mac contributors",
            "USAGE_DESCRIPTION": "USB\\/IP System Extension for sharing USB devices over IP networks",
            "EXTENSION_NAME": "USBIPSystemExtension",
            "USB_INTERFACE_CLASS": "9",
            "USB_VENDOR_ID": "0"
        ]
    }
    
    /// Creates the bash script for Xcode bundle creation
    private func createXcodeBundleScript(
        bundlePath: Path,
        infoPlistTemplate: Path,
        entitlementsFile: Path,
        infoPlist: Path,
        macOSDir: Path,
        resourcesDir: Path,
        templateVars: [String: String]
    ) -> String {
        
        // Create template substitution commands
        var substitutionCommands: [String] = []
        for (key, value) in templateVars {
            substitutionCommands.append("sed -i '' 's/{{\(key)}}/\(value)/g' \"\(infoPlist.string)\"")
        }
        
        let script = """
        #!/bin/bash
        set -e
        
        echo "Creating System Extension bundle (Xcode) at \(bundlePath.string)"
        
        # Create bundle directory structure
        mkdir -p "\(bundlePath.string)"
        mkdir -p "\(bundlePath.string)/Contents/MacOS"
        mkdir -p "\(bundlePath.string)/Contents/Resources"
        
        echo "Bundle directory structure created (Xcode)"
        
        # Copy and process Info.plist template
        if [ -f "\(infoPlistTemplate.string)" ]; then
            cp "\(infoPlistTemplate.string)" "\(infoPlist.string)"
            echo "Info.plist template copied (Xcode)"
            
            # Apply template substitutions
        \(substitutionCommands.joined(separator: "\n    "))
            echo "Template variables substituted (Xcode)"
        else
            echo "Warning: Info.plist template not found at \(infoPlistTemplate.string) (Xcode)"
        fi
        
        # Copy entitlements to Resources
        if [ -f "\(entitlementsFile.string)" ]; then
            cp "\(entitlementsFile.string)" "\(resourcesDir.string)/SystemExtension.entitlements"
            echo "Entitlements copied to bundle (Xcode)"
        else
            echo "Warning: Entitlements file not found at \(entitlementsFile.string) (Xcode)"
        fi
        
        # Note: Executable will be copied by Xcode post-build step
        touch "\(macOSDir.string)/SystemExtension"
        echo "Executable placeholder created (Xcode)"
        
        echo "System Extension bundle creation completed (Xcode)"
        echo "Bundle location: \(bundlePath.string)"
        
        # Set proper permissions
        chmod -R 755 "\(bundlePath.string)"
        echo "Bundle permissions set (Xcode)"
        
        # Code signing (Xcode)
        \(createXcodeCodeSigningCommands(bundlePath: bundlePath, executablePath: macOSDir.appending("SystemExtension"), entitlementsPath: entitlementsFile.string).joined(separator: "\n"))
        
        # Development mode support (Xcode)
        \(createXcodeDevelopmentModeCommands().joined(separator: "\n"))
        """
        
        return script
    }
    
    /// Creates code signing commands for Xcode builds
    private func createXcodeCodeSigningCommands(bundlePath: Path, executablePath: Path, entitlementsPath: String) -> [String] {
        let signingConfig = CodeSigning.Configuration(
            certificateIdentity: nil, // Auto-detect
            developmentMode: true,
            signBundle: true,
            entitlementsPath: entitlementsPath
        )
        
        let xcodeCodeSigning = XcodeCodeSigning(configuration: signingConfig)
        return xcodeCodeSigning.createSigningCommands(bundlePath: bundlePath, executablePath: executablePath)
    }
    
    /// Creates development mode support commands for Xcode
    private func createXcodeDevelopmentModeCommands() -> [String] {
        let signingConfig = CodeSigning.Configuration(
            developmentMode: true,
            entitlementsPath: ""
        )
        
        let xcodeCodeSigning = XcodeCodeSigning(configuration: signingConfig)
        return xcodeCodeSigning.createDevelopmentModeCommands()
    }
}
#endif