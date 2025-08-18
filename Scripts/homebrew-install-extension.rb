#!/usr/bin/env ruby
# frozen_string_literal: true

# Homebrew System Extension Installation Script for usbipd-mac
# This script provides manual System Extension installation for users
# when automatic installation fails or is not possible

require 'json'
require 'fileutils'
require 'pathname'

class HomebrewSystemExtensionInstaller
  BUNDLE_ID = 'com.github.usbipd-mac.systemextension'
  FORMULA_NAME = 'usbipd-mac'
  
  def initialize
    @homebrew_prefix = ENV['HOMEBREW_PREFIX'] || '/opt/homebrew'
    @bundle_path = find_system_extension_bundle
    @verbose = false
  end

  def run(args = ARGV)
    command = args.first&.downcase || 'help'
    @verbose = args.include?('--verbose') || args.include?('-v')
    
    case command
    when 'install'
      install_system_extension
    when 'uninstall'
      uninstall_system_extension
    when 'status'
      show_status
    when 'doctor'
      run_diagnostics
    when 'help', '--help', '-h'
      show_help
    else
      puts "Unknown command: #{command}"
      show_help
      exit 1
    end
  end

  private

  def find_system_extension_bundle
    # Check common Homebrew installation paths
    possible_paths = [
      "#{@homebrew_prefix}/Cellar/#{FORMULA_NAME}/*/Library/SystemExtensions/usbipd-mac.systemextension",
      "#{@homebrew_prefix}/opt/#{FORMULA_NAME}/Library/SystemExtensions/usbipd-mac.systemextension"
    ]
    
    possible_paths.each do |pattern|
      Dir.glob(pattern).each do |path|
        return Pathname.new(path).realpath.to_s if File.exist?(path)
      end
    end
    
    nil
  end

  def install_system_extension
    unless @bundle_path
      puts "❌ Error: System Extension bundle not found"
      puts "   Make sure usbipd-mac is installed via Homebrew: brew install usbipd-mac"
      exit 1
    end

    puts "🔧 Installing System Extension for usbipd-mac..."
    puts "📦 Bundle path: #{@bundle_path}" if @verbose
    
    # Check developer mode status
    developer_mode_enabled = check_developer_mode
    
    if developer_mode_enabled
      puts "✅ Developer mode is enabled - attempting automatic installation"
      attempt_automatic_installation
    else
      puts "⚠️  Developer mode is disabled - manual approval required"
      show_manual_installation_instructions
    end
    
    # Verify installation
    if system_extension_installed?
      puts "✅ System Extension appears to be installed successfully"
      puts "💡 Run 'usbipd-install-extension status' to check detailed status"
    else
      puts "⚠️  System Extension installation may require additional approval"
      puts "   Check System Preferences > Security & Privacy > General"
      puts "   Look for blocked System Extension notification and click 'Allow'"
    end
  end

  def uninstall_system_extension
    puts "🗑️  Uninstalling System Extension for usbipd-mac..."
    
    if system_extension_installed?
      puts "📋 Found installed System Extension"
      puts "⚠️  System Extension removal requires manual action:"
      puts "   1. Open System Preferences > Security & Privacy > General"
      puts "   2. Look for installed extensions in the lower section"
      puts "   3. Remove the USB/IP System Extension"
      puts "   4. A restart may be required"
    else
      puts "ℹ️  No System Extension appears to be installed"
    end
    
    puts "🧹 For complete cleanup, you may also want to:"
    puts "   brew uninstall usbipd-mac"
  end

  def show_status
    puts "📊 System Extension Status for usbipd-mac"
    puts "="*50
    
    puts "Bundle Information:"
    if @bundle_path
      puts "✅ Bundle Path: #{@bundle_path}"
      puts "✅ Bundle ID: #{BUNDLE_ID}"
      
      # Check bundle metadata
      metadata_path = File.join(@bundle_path, 'Contents', 'HomebrewMetadata.json')
      if File.exist?(metadata_path)
        metadata = JSON.parse(File.read(metadata_path))
        puts "📦 Homebrew Version: #{metadata['homebrew_version']}"
        puts "📅 Installation Date: #{metadata['installation_date']}"
      end
    else
      puts "❌ Bundle not found - is usbipd-mac installed?"
    end
    
    puts "\nSystem Configuration:"
    puts "🏠 Homebrew Prefix: #{@homebrew_prefix}"
    puts "🔧 Developer Mode: #{check_developer_mode ? 'Enabled' : 'Disabled'}"
    
    puts "\nSystem Extension Status:"
    installed = system_extension_installed?
    puts "📋 Installation Status: #{installed ? 'Installed' : 'Not Installed'}"
    
    if @verbose
      puts "\nDetailed Extension List:"
      system('systemextensionsctl list 2>/dev/null || echo "Unable to list extensions"')
    end
  end

  def run_diagnostics
    puts "🔍 Running System Extension Diagnostics..."
    puts "="*50
    
    issues = []
    
    # Check bundle presence
    unless @bundle_path
      issues << "System Extension bundle not found"
    end
    
    # Check macOS version
    macos_version = `sw_vers -productVersion`.strip
    if macos_version.split('.').first.to_i < 11
      issues << "macOS Big Sur (11.0) or later required (current: #{macos_version})"
    end
    
    # Check bundle structure
    if @bundle_path
      required_files = [
        'Contents/Info.plist',
        'Contents/MacOS/USBIPDSystemExtension'
      ]
      
      required_files.each do |file|
        unless File.exist?(File.join(@bundle_path, file))
          issues << "Missing required file: #{file}"
        end
      end
    end
    
    # Check permissions
    unless Process.uid == 0
      puts "ℹ️  Note: Some System Extension operations require administrator privileges"
    end
    
    if issues.empty?
      puts "✅ No issues detected"
      puts "💡 If you're still having problems, try:"
      puts "   1. Restart your system"
      puts "   2. Check Security & Privacy preferences"
      puts "   3. Enable developer mode: sudo systemextensionsctl developer on"
    else
      puts "❌ Issues detected:"
      issues.each { |issue| puts "   • #{issue}" }
    end
  end

  def check_developer_mode
    output = `systemextensionsctl developer 2>/dev/null`.strip
    output.include?('enabled')
  rescue
    false
  end

  def system_extension_installed?
    output = `systemextensionsctl list 2>/dev/null`
    output.include?(BUNDLE_ID)
  rescue
    false
  end

  def attempt_automatic_installation
    puts "🚀 Attempting automatic installation..."
    
    # Check if usbipd CLI is available
    usbipd_path = find_usbipd_executable
    unless usbipd_path
      puts "❌ Error: usbipd executable not found"
      puts "   Make sure usbipd-mac is properly installed via Homebrew"
      return false
    end
    
    puts "📋 Using usbipd executable: #{usbipd_path}" if @verbose
    
    # Execute the new CLI installation command
    puts "⚙️  Running: #{usbipd_path} install-system-extension..."
    
    # Use system() to execute the command and capture the exit status
    success = system("#{usbipd_path} install-system-extension --verbose")
    
    if success
      puts "✅ Automatic installation completed successfully"
      
      # Verify installation using enhanced verification
      verification_result = verify_installation_status
      if verification_result[:success]
        puts "✅ Installation verification passed"
        if @verbose && verification_result[:details]
          puts "📊 Verification details:"
          verification_result[:details].each { |detail| puts "   • #{detail}" }
        end
      else
        puts "⚠️  Installation completed but verification found issues:"
        verification_result[:issues].each { |issue| puts "   • #{issue}" }
        if verification_result[:recommendations]
          puts "💡 Recommendations:"
          verification_result[:recommendations].each { |rec| puts "   → #{rec}" }
        end
      end
      
      return true
    else
      exit_code = $?.exitstatus
      puts "❌ Automatic installation failed (exit code: #{exit_code})"
      puts "💡 Fallback to manual installation instructions:"
      show_manual_installation_instructions
      return false
    end
  rescue => e
    puts "❌ Error during automatic installation: #{e.message}"
    puts "💡 Fallback to manual installation instructions:"
    show_manual_installation_instructions
    return false
  end

  def find_usbipd_executable
    # Check common Homebrew installation paths for the usbipd executable
    possible_paths = [
      "#{@homebrew_prefix}/bin/usbipd",
      "#{@homebrew_prefix}/opt/#{FORMULA_NAME}/bin/usbipd",
      "/usr/local/bin/usbipd",  # Intel Mac Homebrew path
      "/opt/homebrew/bin/usbipd" # Apple Silicon Mac Homebrew path
    ]
    
    possible_paths.each do |path|
      return path if File.exist?(path) && File.executable?(path)
    end
    
    # Try to find it in PATH
    which_result = `which usbipd 2>/dev/null`.strip
    return which_result unless which_result.empty?
    
    nil
  end
  
  def verify_installation_status
    # Enhanced verification using comprehensive status checking
    result = {
      success: false,
      details: [],
      issues: [],
      recommendations: []
    }
    
    begin
      # Check if System Extension is registered with macOS
      systemextensionsctl_output = `systemextensionsctl list 2>/dev/null`
      if systemextensionsctl_output.include?(BUNDLE_ID)
        result[:details] << "System Extension is registered with macOS"
        result[:success] = true
      else
        result[:issues] << "System Extension not found in macOS registry"
        result[:recommendations] << "Try restarting the installation process"
        result[:recommendations] << "Check System Preferences > Security & Privacy for approval prompts"
      end
      
      # Check bundle integrity
      if @bundle_path && File.exist?(@bundle_path)
        result[:details] << "System Extension bundle found at #{@bundle_path}"
        
        # Verify bundle structure
        required_files = [
          'Contents/Info.plist',
          'Contents/MacOS/USBIPDSystemExtension'
        ]
        
        missing_files = required_files.select { |file| !File.exist?(File.join(@bundle_path, file)) }
        if missing_files.empty?
          result[:details] << "Bundle structure is valid"
        else
          result[:issues] << "Bundle missing required files: #{missing_files.join(', ')}"
          result[:recommendations] << "Reinstall usbipd-mac via Homebrew"
        end
      else
        result[:issues] << "System Extension bundle not found"
        result[:recommendations] << "Reinstall usbipd-mac via Homebrew"
      end
      
      # Check service status if possible
      if system("brew services list | grep -q usbipd-mac")
        brew_status = `brew services list | grep usbipd-mac`.strip
        if brew_status.include?('started')
          result[:details] << "Homebrew service is running"
        elsif brew_status.include?('stopped')
          result[:details] << "Homebrew service is stopped (this is normal)"
        end
      end
      
      # Check developer mode status
      if check_developer_mode
        result[:details] << "Developer mode is enabled"
      else
        result[:issues] << "Developer mode is disabled"
        result[:recommendations] << "Enable developer mode: sudo systemextensionsctl developer on"
      end
      
    rescue => e
      result[:issues] << "Verification failed: #{e.message}"
      result[:recommendations] << "Run diagnostics: usbipd-install-extension doctor"
    end
    
    # Overall success determination
    result[:success] = result[:issues].empty? || (result[:issues].size == 1 && result[:issues].first.include?("Developer mode"))
    
    result
  end

  def show_manual_installation_instructions
    puts "\n📝 Manual Installation Instructions:"
    puts "="*40
    puts "1. Start the usbipd service to trigger System Extension loading:"
    puts "   sudo brew services start usbipd-mac"
    puts ""
    puts "2. Check System Preferences > Security & Privacy > General"
    puts "   Look for a notification about blocked system software"
    puts ""
    puts "3. Click 'Allow' to approve the System Extension"
    puts ""
    puts "4. Restart your system if prompted"
    puts ""
    puts "5. Verify installation with: usbipd-install-extension status"
    puts ""
    puts "Optional - Enable Developer Mode (easier for future installations):"
    puts "   sudo systemextensionsctl developer on"
    puts "   # Restart required after enabling"
  end

  def show_help
    puts <<~HELP
      usbipd-install-extension - System Extension management for usbipd-mac
      
      USAGE:
        usbipd-install-extension <command> [options]
      
      COMMANDS:
        install     Install the System Extension (manual process)
        uninstall   Uninstall the System Extension (manual process)
        status      Show System Extension installation status
        doctor      Run diagnostics to identify issues
        help        Show this help message
      
      OPTIONS:
        --verbose, -v    Show verbose output
      
      EXAMPLES:
        usbipd-install-extension install
        usbipd-install-extension status --verbose
        usbipd-install-extension doctor
      
      NOTES:
        • System Extensions require macOS Big Sur (11.0) or later
        • Installation may require administrator privileges
        • Manual approval in Security & Privacy settings is usually required
        • Developer mode can simplify the installation process
      
      For more information, visit: https://github.com/beriberikix/usbipd-mac
    HELP
  end
end

# Run the installer if this script is executed directly
if __FILE__ == $0
  HomebrewSystemExtensionInstaller.new.run
end