class UsbipdMacTest < Formula
  desc "Test formula for usbipd-mac System Extension installation validation"
  homepage "https://github.com/beriberikix/usbipd-mac"
  # Use local path instead of remote URL for testing
  url "file:///Users/jberi/code/usbipd-mac"
  version "test-v0.0.6"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000" # Skip SHA verification for local testing
  license "MIT"
  
  depends_on :macos => :big_sur
  depends_on :xcode => ["13.0", :build]
  
  def install
    # Build configuration with System Extension support using release artifacts
    # Use pre-built release binaries from task 7.1
    puts "Using pre-built release binaries from .build/release/"
    
    # Verify that release build artifacts exist
    unless File.exist?(".build/release/usbipd")
      puts "❌ Error: Release build artifacts not found. Run 'swift build --configuration release' first."
      exit 1
    end
    
    unless File.exist?(".build/release/USBIPDSystemExtension")
      puts "❌ Error: System Extension release build not found. Run 'swift build --configuration release --product USBIPDSystemExtension' first."
      exit 1
    end
    
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
        <string>USB/IP System Extension (Test)</string>
        <key>CFBundleExecutable</key>
        <string>USBIPDSystemExtension</string>
        <key>CFBundleIdentifier</key>
        <string>com.github.usbipd-mac.systemextension.test</string>
        <key>CFBundleName</key>
        <string>USBIPDSystemExtension</string>
        <key>CFBundlePackageType</key>
        <string>SYSX</string>
        <key>CFBundleShortVersionString</key>
        <string>#{version}</string>
        <key>CFBundleVersion</key>
        <string>#{version.to_s.gsub(/[^0-9]/, "")}</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>LSMinimumSystemVersion</key>
        <string>11.0</string>
        <key>NSSystemExtensionUsageDescription</key>
        <string>USB/IP System Extension for sharing USB devices over network (Test Installation)</string>
      </dict>
      </plist>
    PLIST
    
    # Write Info.plist
    (sysext_bundle_path/"Contents/Info.plist").write(info_plist_content)
    
    # Create test-specific Homebrew metadata
    sysext_metadata = {
      "homebrew_formula" => "usbipd-mac-test",
      "homebrew_version" => version.to_s,
      "homebrew_prefix" => HOMEBREW_PREFIX.to_s,
      "bundle_identifier" => "com.github.usbipd-mac.systemextension.test",
      "bundle_path" => sysext_bundle_path.to_s,
      "installation_date" => Time.now.iso8601,
      "creator" => "test-formula-validation",
      "test_environment" => true,
      "source_path" => "/Users/jberi/code/usbipd-mac"
    }
    
    # Write metadata as JSON
    require "json"
    (sysext_bundle_path/"Contents/HomebrewMetadata.json").write(JSON.pretty_generate(sysext_metadata))
    
    # Install Homebrew System Extension installation script (use the enhanced version)
    bin.install "Scripts/homebrew-install-extension.rb" => "usbipd-install-extension-test"
    
    puts "✅ Test formula installation completed successfully"
    puts "📦 System Extension bundle: #{sysext_bundle_path}"
    puts "🔧 Management script: #{bin}/usbipd-install-extension-test"
  end
  
  def post_install
    puts "🧪 Running post-installation validation for test formula..."
    puts "="*60
    
    # Test bundle detection using enhanced bundle detector
    sysext_bundle_path = prefix/"Library/SystemExtensions/usbipd-mac.systemextension"
    puts "📦 Testing bundle detection:"
    puts "   Bundle path: #{sysext_bundle_path}"
    puts "   Bundle exists: #{File.exist?(sysext_bundle_path) ? '✅' : '❌'}"
    
    # Test bundle structure
    required_files = [
      "Contents/Info.plist",
      "Contents/MacOS/USBIPDSystemExtension",
      "Contents/HomebrewMetadata.json"
    ]
    
    puts "📋 Testing bundle structure:"
    required_files.each do |file|
      file_path = sysext_bundle_path/file
      exists = File.exist?(file_path)
      puts "   #{file}: #{exists ? '✅' : '❌'}"
    end
    
    # Test CLI integration with new installation command
    puts "🔧 Testing CLI installation command integration:"
    cli_path = bin/"usbipd"
    if File.exist?(cli_path)
      puts "   CLI binary: ✅"
      
      # Test the help system
      help_output = `"#{cli_path}" --help 2>&1`.strip
      if help_output.include?("install-system-extension")
        puts "   Install command available: ✅"
      else
        puts "   Install command available: ❌"
      end
      
      # Test diagnosis command
      if help_output.include?("diagnose")
        puts "   Diagnose command available: ✅"
      else
        puts "   Diagnose command available: ❌"
      end
    else
      puts "   CLI binary: ❌"
    end
    
    # Test management script
    puts "🛠️  Testing management script:"
    mgmt_script = bin/"usbipd-install-extension-test"
    if File.exist?(mgmt_script) && File.executable?(mgmt_script)
      puts "   Management script: ✅"
      
      # Test script functionality (dry run)
      script_help = `"#{mgmt_script}" help 2>&1`.strip
      if script_help.include?("install") && script_help.include?("status")
        puts "   Script functionality: ✅"
      else
        puts "   Script functionality: ❌"
      end
    else
      puts "   Management script: ❌"
    end
    
    puts ""
    puts "🚀 Test Installation Validation Complete"
    puts ""
    puts "Next Steps for Manual Testing:"
    puts "  1. Test bundle detection: #{bin}/usbipd diagnose"
    puts "  2. Test installation: #{bin}/usbipd-install-extension-test install"
    puts "  3. Check status: #{bin}/usbipd-install-extension-test status"
    puts "  4. Test service: sudo brew services start usbipd-mac-test"
    puts ""
    puts "⚠️  Note: This is a test installation with test bundle ID to avoid conflicts"
    puts "    with production installations."
  end
  
  service do
    run [opt_bin/"usbipd", "--daemon"]
    require_root true
    keep_alive true
    run_type :immediate
    log_path var/"log/usbipd-test.log"
    error_log_path var/"log/usbipd-test.error.log"
    working_dir HOMEBREW_PREFIX
    process_type :background
  end
  
  test do
    # Test that the binary runs and shows version
    system "#{bin}/usbipd", "--version"
    
    # Test management script
    system "#{bin}/usbipd-install-extension-test", "help"
    
    # Verify System Extension bundle structure
    assert_predicate prefix/"Library/SystemExtensions/usbipd-mac.systemextension", :exist?
    assert_predicate prefix/"Library/SystemExtensions/usbipd-mac.systemextension/Contents/Info.plist", :exist?
    assert_predicate prefix/"Library/SystemExtensions/usbipd-mac.systemextension/Contents/MacOS/USBIPDSystemExtension", :exist?
    assert_predicate prefix/"Library/SystemExtensions/usbipd-mac.systemextension/Contents/HomebrewMetadata.json", :exist?
    
    # Test that the enhanced bundle detection can find the test installation
    detection_output = `"#{bin}/usbipd" diagnose 2>&1`
    assert_match(/bundle.*found/i, detection_output, "Bundle detection should find the test installation")
    
    puts "✅ All test assertions passed!"
  end
  
  def caveats
    <<~EOS
      🧪 usbipd-mac Test Formula Installation Complete
      ================================================
      
      This is a TEST INSTALLATION for validation purposes.
      
      📦 Installation Details:
        • Bundle ID: com.github.usbipd-mac.systemextension.test
        • Bundle Path: #{prefix}/Library/SystemExtensions/usbipd-mac.systemextension
        • CLI Binary: #{bin}/usbipd
        • Management Script: #{bin}/usbipd-install-extension-test
      
      🧪 Validation Tests:
        1. Bundle Detection Test:
           #{bin}/usbipd diagnose --verbose
        
        2. Installation Workflow Test:
           #{bin}/usbipd-install-extension-test install
        
        3. System Extension Registration Test:
           #{bin}/usbipd install-system-extension --verbose
        
        4. Service Integration Test:
           sudo brew services start usbipd-mac-test
           #{bin}/usbipd status
           sudo brew services stop usbipd-mac-test
        
        5. Verification Test:
           #{bin}/usbipd-install-extension-test status --verbose
      
      ⚠️  Important Notes:
        • This uses a TEST bundle ID to avoid conflicts with production
        • Manual approval may be required in Security & Privacy settings
        • Developer mode recommended for easier testing: sudo systemextensionsctl developer on
        • Service logs: #{var}/log/usbipd-test.log
      
      🗑️  Cleanup After Testing:
        brew uninstall usbipd-mac-test
        # System Extension may need manual removal via System Preferences
      
      📊 Test Results Expected:
        ✅ Bundle detection in Homebrew paths
        ✅ CLI installation command integration
        ✅ Management script functionality
        ✅ System Extension approval workflow
        ✅ Service management integration
        ✅ Installation verification
    EOS
  end
end