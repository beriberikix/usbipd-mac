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
        <string>#{version.gsub(".", "")}</string>
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
    <<~EOS
      usbipd-mac requires System Extension approval and administrator privileges.
      
      The System Extension bundle has been installed to:
        #{prefix}/Library/SystemExtensions/usbipd-mac.systemextension
      
      System Extension Management:
      1. Install: usbipd-sysext install
      2. Status:  usbipd-sysext status
      3. Remove:  usbipd-sysext uninstall
      
      Manual Installation Steps (if automatic fails):
      1. Check System Preferences > Security & Privacy > General
      2. Look for "System Extension Blocked" notification
      3. Click "Allow" to approve the extension
      4. A restart may be required for the System Extension to become active
      
      Developer Mode (optional, for easier installation):
        sudo systemextensionsctl developer on
        # Restart required after enabling
      
      To start the service:
        sudo brew services start usbipd-mac
      
      To check overall status:
        usbipd status
        usbipd-sysext status
    EOS
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