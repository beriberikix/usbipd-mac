import Foundation
import PackagePlugin

/// Handles code signing for System Extension bundles
struct CodeSigning {
    
    /// Configuration for code signing
    struct Configuration {
        let certificateIdentity: String?
        let developmentMode: Bool
        let signBundle: Bool
        let entitlementsPath: String
        
        init(certificateIdentity: String? = nil, 
             developmentMode: Bool = true, 
             signBundle: Bool = true,
             entitlementsPath: String) {
            self.certificateIdentity = certificateIdentity
            self.developmentMode = developmentMode
            self.signBundle = signBundle
            self.entitlementsPath = entitlementsPath
        }
    }
    
    private let configuration: Configuration
    
    init(configuration: Configuration) {
        self.configuration = configuration
    }
    
    /// Creates code signing commands for the bundle
    func createSigningCommands(bundlePath: Path, executablePath: Path) -> [String] {
        var commands: [String] = []
        
        if !configuration.signBundle {
            commands.append("echo \"Code signing disabled\"")
            return commands
        }
        
        if configuration.developmentMode {
            commands.append("echo \"Development mode: checking for code signing certificates\"")
            commands.append(createCertificateDetectionCommand())
        }
        
        // Detect appropriate signing identity
        let signingIdentity = configuration.certificateIdentity ?? detectSigningIdentity()
        
        if signingIdentity.isEmpty || signingIdentity == "DEVELOPMENT_MODE" {
            commands.append("echo \"No code signing certificate found - creating unsigned bundle for development\"")
            commands.append("echo \"Note: Unsigned bundles require systemextensionsctl developer mode\"")
            return commands
        }
        
        // Sign the executable first
        commands.append(createExecutableSigningCommand(
            executablePath: executablePath,
            signingIdentity: signingIdentity
        ))
        
        // Sign the bundle
        commands.append(createBundleSigningCommand(
            bundlePath: bundlePath,
            signingIdentity: signingIdentity
        ))
        
        // Verify the signature
        commands.append(createSignatureVerificationCommand(bundlePath: bundlePath))
        
        return commands
    }
    
    /// Creates a command to detect available certificates
    private func createCertificateDetectionCommand() -> String {
        return """
        # Check for available System Extension signing certificates
        if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
            echo "Found Developer ID Application certificate"
        elif security find-identity -v -p codesigning | grep -q "Mac Developer"; then
            echo "Found Mac Developer certificate"
        elif security find-identity -v -p codesigning | grep -q "Apple Development"; then
            echo "Found Apple Development certificate"
        else
            echo "No suitable code signing certificates found"
            echo "System Extension will be unsigned (development mode only)"
        fi
        """
    }
    
    /// Detects the appropriate signing identity to use
    private func detectSigningIdentity() -> String {
        // In a real implementation, this would run security commands
        // For the plugin, we'll return a placeholder that the script will resolve
        return "AUTO_DETECT"
    }
    
    /// Creates command to sign the executable
    private func createExecutableSigningCommand(executablePath: Path, signingIdentity: String) -> String {
        if signingIdentity == "AUTO_DETECT" {
            return createAutoDetectExecutableSigningCommand(executablePath: executablePath)
        }
        
        return """
        # Sign the executable
        echo "Signing executable at \(executablePath.string)"
        codesign --force --sign "\(signingIdentity)" \\
            --entitlements "\(configuration.entitlementsPath)" \\
            --options runtime \\
            "\(executablePath.string)"
        echo "Executable signed successfully"
        """
    }
    
    /// Creates auto-detecting executable signing command
    private func createAutoDetectExecutableSigningCommand(executablePath: Path) -> String {
        return """
        # Auto-detect and sign executable
        echo "Auto-detecting signing identity for executable"
        
        # Try to find the best available certificate
        SIGNING_IDENTITY=""
        if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
            SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -n1 | awk '{print $2}')
            echo "Using Developer ID Application: $SIGNING_IDENTITY"
        elif security find-identity -v -p codesigning | grep -q "Mac Developer"; then
            SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Mac Developer" | head -n1 | awk '{print $2}')
            echo "Using Mac Developer: $SIGNING_IDENTITY"
        elif security find-identity -v -p codesigning | grep -q "Apple Development"; then
            SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -n1 | awk '{print $2}')
            echo "Using Apple Development: $SIGNING_IDENTITY"
        fi
        
        if [ -n "$SIGNING_IDENTITY" ]; then
            echo "Signing executable at \(executablePath.string)"
            codesign --force --sign "$SIGNING_IDENTITY" \\
                --entitlements "\(configuration.entitlementsPath)" \\
                --options runtime \\
                "\(executablePath.string)"
            echo "Executable signed successfully with $SIGNING_IDENTITY"
        else
            echo "No signing identity found - leaving executable unsigned"
        fi
        """
    }
    
    /// Creates command to sign the bundle
    private func createBundleSigningCommand(bundlePath: Path, signingIdentity: String) -> String {
        if signingIdentity == "AUTO_DETECT" {
            return createAutoDetectBundleSigningCommand(bundlePath: bundlePath)
        }
        
        return """
        # Sign the bundle
        echo "Signing bundle at \(bundlePath.string)"
        codesign --force --sign "\(signingIdentity)" \\
            --entitlements "\(configuration.entitlementsPath)" \\
            --options runtime \\
            "\(bundlePath.string)"
        echo "Bundle signed successfully"
        """
    }
    
    /// Creates auto-detecting bundle signing command
    private func createAutoDetectBundleSigningCommand(bundlePath: Path) -> String {
        return """
        # Auto-detect and sign bundle
        echo "Auto-detecting signing identity for bundle"
        
        # Use the same identity detection as executable
        SIGNING_IDENTITY=""
        if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
            SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -n1 | awk '{print $2}')
            echo "Using Developer ID Application: $SIGNING_IDENTITY"
        elif security find-identity -v -p codesigning | grep -q "Mac Developer"; then
            SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Mac Developer" | head -n1 | awk '{print $2}')
            echo "Using Mac Developer: $SIGNING_IDENTITY"
        elif security find-identity -v -p codesigning | grep -q "Apple Development"; then
            SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -n1 | awk '{print $2}')
            echo "Using Apple Development: $SIGNING_IDENTITY"
        fi
        
        if [ -n "$SIGNING_IDENTITY" ]; then
            echo "Signing bundle at \(bundlePath.string)"
            codesign --force --sign "$SIGNING_IDENTITY" \\
                --entitlements "\(configuration.entitlementsPath)" \\
                --options runtime \\
                "\(bundlePath.string)"
            echo "Bundle signed successfully with $SIGNING_IDENTITY"
        else
            echo "No signing identity found - leaving bundle unsigned"
            echo "For development: Enable system extension developer mode with:"
            echo "systemextensionsctl developer on"
        fi
        """
    }
    
    /// Creates command to verify the signature
    private func createSignatureVerificationCommand(bundlePath: Path) -> String {
        return """
        # Verify bundle signature
        echo "Verifying bundle signature"
        if codesign --verify --deep --strict "\(bundlePath.string)" 2>/dev/null; then
            echo "Bundle signature verification successful"
            
            # Display signature information
            echo "Bundle signature details:"
            codesign --display --verbose=2 "\(bundlePath.string)" 2>&1 || true
        else
            echo "Bundle is unsigned or signature verification failed"
            echo "This is normal in development mode"
        fi
        """
    }
    
    /// Creates development mode support commands
    func createDevelopmentModeCommands() -> [String] {
        return [
            """
            # Check system extension developer mode status
            echo "Checking system extension developer mode status"
            if systemextensionsctl developer 2>/dev/null | grep -q "enabled"; then
                echo "System extension developer mode is enabled"
            else
                echo "System extension developer mode is NOT enabled"
                echo "To enable developer mode (required for unsigned extensions):"
                echo "  sudo systemextensionsctl developer on"
                echo ""
                echo "Note: Developer mode allows loading unsigned system extensions"
                echo "This is required during development but should be disabled in production"
            fi
            """
        ]
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

/// Xcode-specific code signing support
struct XcodeCodeSigning {
    private let configuration: CodeSigning.Configuration
    
    init(configuration: CodeSigning.Configuration) {
        self.configuration = configuration
    }
    
    /// Creates code signing commands for Xcode builds
    func createSigningCommands(bundlePath: Path, executablePath: Path) -> [String] {
        let codeSigning = CodeSigning(configuration: configuration)
        var commands = codeSigning.createSigningCommands(bundlePath: bundlePath, executablePath: executablePath)
        
        // Add Xcode-specific signing considerations
        commands.insert("echo \"Xcode build: Code signing System Extension bundle\"", at: 0)
        
        return commands
    }
    
    /// Creates development mode support for Xcode
    func createDevelopmentModeCommands() -> [String] {
        let codeSigning = CodeSigning(configuration: configuration)
        var commands = codeSigning.createDevelopmentModeCommands()
        
        // Add Xcode-specific development mode info
        commands.append("""
        echo "Xcode development notes:"
        echo "- Xcode may handle some code signing automatically"
        echo "- Ensure your project has proper signing settings"
        echo "- System Extension targets require specific entitlements"
        """)
        
        return commands
    }
}
#endif