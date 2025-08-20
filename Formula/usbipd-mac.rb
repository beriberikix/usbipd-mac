class UsbipdMac < Formula
  desc "macOS USB/IP protocol implementation for sharing USB devices over IP"
  homepage "https://github.com/beriberikix/usbipd-mac"
  url "https://github.com/beriberikix/usbipd-mac/archive/VERSION_PLACEHOLDER.tar.gz"
  version "VERSION_PLACEHOLDER"
  sha256 "SHA256_PLACEHOLDER"
  license "MIT"
  
  depends_on :macos => :big_sur
  depends_on :xcode => ["13.0", :build]
  
  def install
    # Build configuration with System Extension support
    system "swift", "build", "--configuration", "release", "--disable-sandbox"
    
    # Build System Extension product separately
    system "swift", "build", "--configuration", "release", "--product", "USBIPDSystemExtension", "--disable-sandbox"
    
    # Install the main binary
    bin.install ".build/release/usbipd"
    
    # Create System Extension bundle structure
    sysext_bundle_path = prefix/"Library/SystemExtensions/usbipd-mac.systemextension"
    
    # Create bundle directory structure
    (sysext_bundle_path/"Contents").mkpath
    (sysext_bundle_path/"Contents/MacOS").mkpath
    (sysext_bundle_path/"Contents/Resources").mkpath
    
    # Install System Extension executable
    (sysext_bundle_path/"Contents/MacOS").install ".build/release/USBIPDSystemExtension"
    
    # Create Info.plist for System Extension
    info_plist_content = <<~PLIST
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleDisplayName</key>
        <string>USB/IP System Extension</string>
        <key>CFBundleExecutable</key>
        <string>USBIPDSystemExtension</string>
        <key>CFBundleIdentifier</key>
        <string>com.github.usbipd-mac.systemextension</string>
        <key>CFBundleName</key>
        <string>USBIPDSystemExtension</string>
        <key>CFBundlePackageType</key>
        <string>SYSX</string>
        <key>CFBundleShortVersionString</key>
        <string>#{version}</string>
        <key>CFBundleVersion</key>
        <string>#{version.to_s.gsub(".", "")}</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>LSMinimumSystemVersion</key>
        <string>11.0</string>
        <key>NSSystemExtensionUsageDescription</key>
        <string>USB/IP System Extension for sharing USB devices over network</string>
      </dict>
      </plist>
    PLIST
    
    # Write Info.plist
    (sysext_bundle_path/"Contents/Info.plist").write(info_plist_content)
    
    # Create convenience script for System Extension management
    sysext_manager_script = <<~SCRIPT
      #!/bin/bash
      # System Extension management script for usbipd-mac
      
      BUNDLE_PATH="#{sysext_bundle_path}"
      BUNDLE_ID="com.github.usbipd-mac.systemextension"
      
      case "$1" in
        install)
          echo "Installing System Extension..."
          echo "Bundle path: $BUNDLE_PATH"
          
          # Check if developer mode is enabled
          if systemextensionsctl developer | grep -q "enabled"; then
            echo "Developer mode is enabled - attempting automatic installation"
            osascript -e "tell application \"System Events\" to display dialog \"System Extension installation may require approval in Security & Privacy settings.\" buttons {\"OK\"} default button \"OK\""
          else
            echo "Developer mode is disabled - manual approval required"
            echo "1. Check System Preferences > Security & Privacy > General"
            echo "2. Look for blocked System Extension notification"
            echo "3. Click 'Allow' to approve the extension"
            echo ""
            echo "To enable developer mode (optional):"
            echo "  sudo systemextensionsctl developer on"
            echo "  # Restart required after enabling"
          fi
          ;;
        uninstall)
          echo "Uninstalling System Extension..."
          systemextensionsctl list | grep "$BUNDLE_ID" && {
            echo "Found installed System Extension, removing..."
            # Note: Actual uninstallation requires system-level operations
            echo "System Extension may require manual removal through System Preferences"
          }
          ;;
        status)
          echo "System Extension Status:"
          echo "Bundle ID: $BUNDLE_ID"
          echo "Bundle Path: $BUNDLE_PATH"
          echo "Developer Mode: $(systemextensionsctl developer)"
          echo ""
          echo "Installed Extensions:"
          systemextensionsctl list | grep -E "(identifier|$BUNDLE_ID)" || echo "No matching extensions found"
          ;;
        *)
          echo "Usage: $0 {install|uninstall|status}"
          echo ""
          echo "Commands:"
          echo "  install   - Install the System Extension"
          echo "  uninstall - Uninstall the System Extension"
          echo "  status    - Show System Extension status"
          exit 1
          ;;
      esac
    SCRIPT
    
    # Install System Extension management script
    (bin/"usbipd-sysext").write(sysext_manager_script)
    (bin/"usbipd-sysext").chmod(0755)
    
    # Create Homebrew metadata for the System Extension
    sysext_metadata = {
      "homebrew_formula" => "usbipd-mac",
      "homebrew_version" => version.to_s,
      "homebrew_prefix" => HOMEBREW_PREFIX.to_s,
      "bundle_identifier" => "com.github.usbipd-mac.systemextension",
      "bundle_path" => sysext_bundle_path.to_s,
      "installation_date" => Time.now.iso8601,
      "creator" => "homebrew-formula-enhanced"
    }
    
    # Write metadata as JSON
    require "json"
    (sysext_bundle_path/"Contents/HomebrewMetadata.json").write(JSON.pretty_generate(sysext_metadata))
    
    # Install Homebrew System Extension installation script
    bin.install "Scripts/homebrew-install-extension.rb" => "usbipd-install-extension"
  end
  
  def post_install
    # Attempt automatic System Extension installation after Homebrew installation
    puts "🔧 Configuring System Extension for usbipd-mac..."
    
    # Check if developer mode is enabled for automatic installation
    developer_mode_output = `systemextensionsctl developer 2>/dev/null`.strip rescue ""
    developer_mode_enabled = developer_mode_output.downcase.include?("enabled")
    
    if developer_mode_enabled
      puts "✅ Developer mode is enabled - attempting automatic installation"
      
      # Attempt to trigger System Extension loading by starting and stopping the service
      begin
        puts "🚀 Triggering System Extension installation..."
        system("sudo", "brew", "services", "start", "usbipd-mac", "--quiet")
        sleep(2) # Give the extension time to load
        
        # Check if the extension was successfully installed
        extension_output = `systemextensionsctl list 2>/dev/null | grep "com.github.usbipd-mac.systemextension"`.strip rescue ""
        
        if !extension_output.empty?
          puts "✅ System Extension installed successfully!"
          puts "💡 The service has been started. Run 'usbipd status' to verify operation."
        else
          puts "⚠️  System Extension installation may require approval"
          puts "   Check System Preferences > Security & Privacy > General"
          puts "   Look for blocked System Extension notification and click 'Allow'"
        end
        
        # Stop the service if it was started for installation only
        system("sudo", "brew", "services", "stop", "usbipd-mac", "--quiet")
        
      rescue => e
        puts "⚠️  Automatic installation failed: #{e.message}"
        puts "   You can install manually using: usbipd-install-extension install"
      end
      
    else
      puts "⚠️  Developer mode is disabled - manual installation required"
      puts ""
      puts "Choose one of these options:"
      puts ""
      puts "Option 1: Enable developer mode (easier for future updates)"
      puts "  sudo systemextensionsctl developer on"
      puts "  # Restart required after enabling"
      puts "  brew reinstall usbipd-mac"
      puts ""
      puts "Option 2: Manual installation"
      puts "  usbipd-install-extension install"
      puts ""
    end
    
    puts "📋 System Extension management commands:"
    puts "  Install:    usbipd-install-extension install"
    puts "  Status:     usbipd-install-extension status" 
    puts "  Uninstall:  usbipd-install-extension uninstall"
    puts "  Diagnose:   usbipd-install-extension doctor"
  end
  
  service do
    run [opt_bin/"usbipd", "--daemon"]
    require_root true
    keep_alive true
    run_type :immediate
    log_path var/"log/usbipd.log"
    error_log_path var/"log/usbipd.error.log"
    working_dir HOMEBREW_PREFIX
    process_type :background
  end
  
  def caveats
    # Check current installation state to provide dynamic guidance
    developer_mode_output = `systemextensionsctl developer 2>/dev/null`.strip rescue ""
    developer_mode_enabled = developer_mode_output.downcase.include?("enabled")
    
    extension_output = `systemextensionsctl list 2>/dev/null | grep "com.github.usbipd-mac.systemextension"`.strip rescue ""
    extension_installed = !extension_output.empty?
    
    caveats_text = []
    
    # Header
    caveats_text << "🔧 usbipd-mac System Extension Setup"
    caveats_text << "===================================="
    caveats_text << ""
    
    # Dynamic status information
    caveats_text << "Current Status:"
    caveats_text << "  📦 Bundle Location: #{prefix}/Library/SystemExtensions/usbipd-mac.systemextension"
    caveats_text << "  🔧 Developer Mode: #{developer_mode_enabled ? 'Enabled ✅' : 'Disabled ❌'}"
    caveats_text << "  📋 System Extension: #{extension_installed ? 'Installed ✅' : 'Not Installed ❌'}"
    caveats_text << ""
    
    # Provide guidance based on current state
    if extension_installed
      caveats_text << "✅ System Extension is installed and ready!"
      caveats_text << ""
      caveats_text << "Next Steps:"
      caveats_text << "  1. Start the service: sudo brew services start usbipd-mac"
      caveats_text << "  2. Check status: usbipd status"
      caveats_text << "  3. Verify operation: usbipd-install-extension status"
      
    elsif developer_mode_enabled
      caveats_text << "⚠️  System Extension not yet installed (developer mode enabled)"
      caveats_text << ""
      caveats_text << "Installation Options:"
      caveats_text << "  Option 1 (Automatic): usbipd-install-extension install"
      caveats_text << "  Option 2 (Service):    sudo brew services start usbipd-mac"
      caveats_text << ""
      caveats_text << "If automatic installation requires approval:"
      caveats_text << "  • Check System Preferences > Security & Privacy > General"
      caveats_text << "  • Look for blocked System Extension notification"
      caveats_text << "  • Click 'Allow' to approve the extension"
      
    else
      caveats_text << "⚠️  System Extension requires setup (developer mode disabled)"
      caveats_text << ""
      caveats_text << "Choose one of these installation methods:"
      caveats_text << ""
      caveats_text << "Method 1: Enable Developer Mode (Recommended for easier management)"
      caveats_text << "  1. Enable developer mode:"
      caveats_text << "     sudo systemextensionsctl developer on"
      caveats_text << "  2. Restart your Mac (required)"
      caveats_text << "  3. Reinstall for automatic setup:"
      caveats_text << "     brew reinstall usbipd-mac"
      caveats_text << ""
      caveats_text << "Method 2: Manual Installation"
      caveats_text << "  1. Run the installation helper:"
      caveats_text << "     usbipd-install-extension install"
      caveats_text << "  2. Follow the on-screen instructions"
      caveats_text << "  3. Approve in Security & Privacy settings when prompted"
    end
    
    caveats_text << ""
    caveats_text << "📋 System Extension Management Commands:"
    caveats_text << "  • Install:    usbipd-install-extension install"
    caveats_text << "  • Status:     usbipd-install-extension status"
    caveats_text << "  • Uninstall:  usbipd-install-extension uninstall"
    caveats_text << "  • Diagnose:   usbipd-install-extension doctor"
    caveats_text << ""
    caveats_text << "🚀 Service Management:"
    caveats_text << "  • Start:      sudo brew services start usbipd-mac"
    caveats_text << "  • Stop:       sudo brew services stop usbipd-mac"
    caveats_text << "  • Status:     brew services list | grep usbipd-mac"
    caveats_text << ""
    caveats_text << "🔍 Troubleshooting:"
    caveats_text << "  • Check overall status: usbipd status"
    caveats_text << "  • Run diagnostics: usbipd-install-extension doctor"
    caveats_text << "  • View logs: tail -f #{var}/log/usbipd.log"
    caveats_text << ""
    caveats_text << "📚 Additional Information:"
    caveats_text << "  • System Extensions require macOS 11.0+ (Big Sur or later)"
    caveats_text << "  • Administrator privileges are required for installation and operation"
    caveats_text << "  • Network sharing requires firewall configuration"
    caveats_text << ""
    caveats_text << "🆘 Need Help?"
    caveats_text << "  • Documentation: https://github.com/beriberikix/usbipd-mac"
    caveats_text << "  • Issues: https://github.com/beriberikix/usbipd-mac/issues"
    caveats_text << "  • Run doctor: usbipd-install-extension doctor"
    
    caveats_text.join("\n")
  end
  
  test do
    # Test that the binary runs and shows version
    system "#{bin}/usbipd", "--version"
    
    # Test System Extension management script
    system "#{bin}/usbipd-sysext", "status"
    
    # Verify System Extension bundle structure
    assert_predicate prefix/"Library/SystemExtensions/usbipd-mac.systemextension", :exist?
    assert_predicate prefix/"Library/SystemExtensions/usbipd-mac.systemextension/Contents/Info.plist", :exist?
    assert_predicate prefix/"Library/SystemExtensions/usbipd-mac.systemextension/Contents/MacOS/USBIPDSystemExtension", :exist?
    assert_predicate prefix/"Library/SystemExtensions/usbipd-mac.systemextension/Contents/HomebrewMetadata.json", :exist?
  end
end