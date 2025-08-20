#!/usr/bin/env ruby
# frozen_string_literal: true

# update-formula.rb
# Ruby script for updating Homebrew formula template with version and checksum placeholders
# Designed for safe and validated formula updates in the tap repository workflow

require 'json'
require 'optparse'
require 'tempfile'

class FormulaUpdater
  EXIT_SUCCESS = 0
  EXIT_VALIDATION_FAILED = 1
  EXIT_FORMULA_NOT_FOUND = 2
  EXIT_UPDATE_FAILED = 3
  EXIT_USAGE_ERROR = 6

  def initialize
    @options = {
      formula_file: nil,
      version: nil,
      sha256: nil,
      archive_url: nil,
      dry_run: false,
      validate_syntax: true,
      backup: true,
      verbose: false
    }
    @backup_file = nil
  end

  def run(args)
    parse_options(args)
    validate_options
    
    log_info "Starting formula update process..."
    log_info "Formula file: #{@options[:formula_file]}"
    log_info "Version: #{@options[:version]}"
    log_info "SHA256: #{@options[:sha256]}"
    log_info "Archive URL: #{@options[:archive_url]}" if @options[:archive_url]
    log_info "Dry run: #{@options[:dry_run]}"
    
    validate_formula_file
    create_backup if @options[:backup]
    update_formula
    validate_syntax if @options[:validate_syntax]
    
    if @options[:dry_run]
      log_success "✅ Formula update validation completed (dry run)"
      restore_backup if @backup_file
    else
      log_success "✅ Formula updated successfully"
      cleanup_backup if @backup_file
    end
    
    EXIT_SUCCESS
  rescue StandardError => e
    log_error "Formula update failed: #{e.message}"
    restore_backup if @backup_file && !@options[:dry_run]
    EXIT_UPDATE_FAILED
  end

  private

  def parse_options(args)
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
      opts.separator ""
      opts.separator "Ruby script for updating Homebrew formula template with version and checksum"
      opts.separator ""
      opts.separator "Required options:"
      
      opts.on("-f", "--formula-file FILE", "Path to formula file") do |file|
        @options[:formula_file] = file
      end
      
      opts.on("-v", "--version VERSION", "Release version (e.g., v1.2.3)") do |version|
        @options[:version] = version
      end
      
      opts.on("-s", "--sha256 CHECKSUM", "SHA256 checksum") do |sha256|
        @options[:sha256] = sha256
      end
      
      opts.separator ""
      opts.separator "Optional options:"
      
      opts.on("-u", "--archive-url URL", "Archive URL (for validation)") do |url|
        @options[:archive_url] = url
      end
      
      opts.on("-d", "--dry-run", "Preview changes without modifying files") do
        @options[:dry_run] = true
      end
      
      opts.on("--no-syntax-validation", "Skip Ruby syntax validation") do
        @options[:validate_syntax] = false
      end
      
      opts.on("--no-backup", "Skip creating backup of formula file") do
        @options[:backup] = false
      end
      
      opts.on("--verbose", "Enable verbose output") do
        @options[:verbose] = true
      end
      
      opts.on("-h", "--help", "Show this help message") do
        puts opts
        exit EXIT_SUCCESS
      end
    end
    
    parser.parse!(args)
  rescue OptionParser::InvalidOption => e
    log_error e.message
    exit EXIT_USAGE_ERROR
  end

  def validate_options
    required_options = [:formula_file, :version, :sha256]
    missing_options = required_options.select { |opt| @options[opt].nil? || @options[opt].empty? }
    
    unless missing_options.empty?
      log_error "Missing required options: #{missing_options.join(', ')}"
      exit EXIT_USAGE_ERROR
    end
    
    # Validate version format
    unless @options[:version].match?(/^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$/)
      log_error "Invalid version format: #{@options[:version]}"
      log_error "Expected format: vX.Y.Z or vX.Y.Z-suffix"
      exit EXIT_VALIDATION_FAILED
    end
    
    # Validate SHA256 format
    unless @options[:sha256].match?(/^[a-fA-F0-9]{64}$/)
      log_error "Invalid SHA256 checksum format: #{@options[:sha256]}"
      log_error "Expected: 64-character hexadecimal string"
      exit EXIT_VALIDATION_FAILED
    end
  end

  def validate_formula_file
    formula_file = @options[:formula_file]
    
    unless File.exist?(formula_file)
      log_error "Formula file not found: #{formula_file}"
      exit EXIT_FORMULA_NOT_FOUND
    end
    
    unless File.readable?(formula_file)
      log_error "Formula file is not readable: #{formula_file}"
      exit EXIT_FORMULA_NOT_FOUND
    end
    
    unless formula_file.end_with?('.rb')
      log_error "Formula file must have .rb extension: #{formula_file}"
      exit EXIT_VALIDATION_FAILED
    end
    
    log_info "✓ Formula file validation passed"
  end

  def create_backup
    return if @options[:dry_run]
    
    formula_file = @options[:formula_file]
    timestamp = Time.now.strftime("%Y%m%d-%H%M%S")
    @backup_file = "#{formula_file}.backup-#{timestamp}"
    
    begin
      File.copy_stream(formula_file, @backup_file)
      log_info "✓ Backup created: #{File.basename(@backup_file)}"
    rescue StandardError => e
      log_error "Failed to create backup: #{e.message}"
      raise
    end
  end

  def update_formula
    formula_file = @options[:formula_file]
    content = File.read(formula_file)
    original_content = content.dup
    
    log_info "Updating formula content..."
    
    # Update archive URL in formula
    version = @options[:version]
    content = update_archive_url(content, version)
    
    # Update version string
    content = update_version_string(content, version)
    
    # Update SHA256 checksum
    content = update_sha256_checksum(content, @options[:sha256])
    
    # Validate that updates were applied
    validate_updates(content, version, @options[:sha256])
    
    if @options[:dry_run]
      log_info "DRY RUN: Formula updates validated successfully"
      log_verbose "Updated content preview:"
      log_verbose content.lines.first(20).join if @options[:verbose]
    else
      # Write updated content to file
      File.write(formula_file, content)
      log_info "✓ Formula file updated successfully"
    end
    
    # Check for any remaining placeholders
    check_remaining_placeholders(content)
  end

  def update_archive_url(content, version)
    log_info "Updating archive URL with version #{version}..."
    
    # Pattern to match GitHub archive URLs
    url_pattern = /archive\/v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?\.tar\.gz/
    new_url_part = "archive/#{version}.tar.gz"
    
    unless content.match?(url_pattern)
      log_error "Archive URL pattern not found in formula"
      log_error "Expected pattern: archive/vX.Y.Z.tar.gz"
      raise "Archive URL pattern not found"
    end
    
    updated_content = content.gsub(url_pattern, new_url_part)
    
    if updated_content == content
      log_warning "Archive URL was not updated (may already be correct)"
    else
      log_info "✓ Archive URL updated to: #{new_url_part}"
    end
    
    updated_content
  end

  def update_version_string(content, version)
    log_info "Updating version string to #{version}..."
    
    # Pattern to match version declarations
    version_pattern = /version\s+"v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?"/
    new_version_string = "version \"#{version}\""
    
    unless content.match?(version_pattern)
      log_error "Version string pattern not found in formula"
      log_error "Expected pattern: version \"vX.Y.Z\""
      raise "Version string pattern not found"
    end
    
    updated_content = content.gsub(version_pattern, new_version_string)
    
    if updated_content == content
      log_warning "Version string was not updated (may already be correct)"
    else
      log_info "✓ Version string updated to: #{new_version_string}"
    end
    
    updated_content
  end

  def update_sha256_checksum(content, checksum)
    log_info "Updating SHA256 checksum..."
    
    # Pattern to match SHA256 declarations
    sha256_pattern = /sha256\s+"[a-fA-F0-9]{64}"/
    new_sha256_string = "sha256 \"#{checksum}\""
    
    unless content.match?(sha256_pattern)
      log_error "SHA256 pattern not found in formula"
      log_error "Expected pattern: sha256 \"[64-char-hex]\""
      raise "SHA256 pattern not found"
    end
    
    updated_content = content.gsub(sha256_pattern, new_sha256_string)
    
    if updated_content == content
      log_warning "SHA256 checksum was not updated (may already be correct)"
    else
      log_info "✓ SHA256 checksum updated"
    end
    
    updated_content
  end

  def validate_updates(content, version, sha256)
    log_info "Validating formula updates..."
    
    errors = []
    
    # Check that version is present
    unless content.include?("version \"#{version}\"")
      errors << "Version #{version} not found in updated formula"
    end
    
    # Check that SHA256 is present
    unless content.include?("sha256 \"#{sha256}\"")
      errors << "SHA256 checksum not found in updated formula"
    end
    
    # Check that archive URL contains the version
    unless content.include?("archive/#{version}.tar.gz")
      errors << "Archive URL with version #{version} not found in updated formula"
    end
    
    unless errors.empty?
      log_error "Formula update validation failed:"
      errors.each { |error| log_error "  - #{error}" }
      raise "Formula update validation failed"
    end
    
    log_info "✓ Formula update validation passed"
  end

  def check_remaining_placeholders(content)
    placeholders = [
      'VERSION_PLACEHOLDER',
      'SHA256_PLACEHOLDER',
      '{{VERSION}}',
      '{{SHA256}}',
      '{{CHECKSUM}}'
    ]
    
    found_placeholders = placeholders.select { |placeholder| content.include?(placeholder) }
    
    unless found_placeholders.empty?
      log_warning "Found unreplaced placeholders in formula:"
      found_placeholders.each { |placeholder| log_warning "  - #{placeholder}" }
      log_warning "These may need manual attention"
    end
  end

  def validate_syntax
    return if @options[:dry_run]
    
    log_info "Validating Ruby syntax..."
    
    formula_file = @options[:formula_file]
    
    # Use Ruby to check syntax
    result = system("ruby", "-c", formula_file, out: File::NULL, err: File::NULL)
    
    if result
      log_info "✓ Ruby syntax validation passed"
    else
      log_error "✗ Ruby syntax validation failed"
      
      # Get detailed syntax error information
      syntax_output = `ruby -c "#{formula_file}" 2>&1`
      log_error "Syntax error details:"
      syntax_output.lines.each { |line| log_error "  #{line.chomp}" }
      
      raise "Ruby syntax validation failed"
    end
    
    # Additional Homebrew formula structure validation
    validate_homebrew_structure
  end

  def validate_homebrew_structure
    log_info "Validating Homebrew formula structure..."
    
    content = File.read(@options[:formula_file])
    errors = []
    
    # Check for required Homebrew formula components
    required_components = [
      /class\s+\w+\s*<\s*Formula/,           # Class definition
      /desc\s+["']/,                        # Description
      /homepage\s+["']/,                    # Homepage
      /url\s+["']/,                         # URL
      /version\s+["']/,                     # Version
      /sha256\s+["']/,                      # SHA256
      /def\s+install/                       # Install method
    ]
    
    required_components.each_with_index do |pattern, index|
      component_names = [
        'Formula class definition',
        'Description field',
        'Homepage field', 
        'URL field',
        'Version field',
        'SHA256 field',
        'Install method'
      ]
      
      unless content.match?(pattern)
        errors << "Missing #{component_names[index]}"
      end
    end
    
    unless errors.empty?
      log_error "Homebrew formula structure validation failed:"
      errors.each { |error| log_error "  - #{error}" }
      raise "Homebrew formula structure validation failed"
    end
    
    log_info "✓ Homebrew formula structure validation passed"
  end

  def restore_backup
    return unless @backup_file && File.exist?(@backup_file)
    
    log_info "Restoring formula from backup..."
    File.copy_stream(@backup_file, @options[:formula_file])
    File.delete(@backup_file)
    log_info "✓ Formula restored from backup"
  rescue StandardError => e
    log_error "Failed to restore backup: #{e.message}"
  end

  def cleanup_backup
    return unless @backup_file && File.exist?(@backup_file)
    
    File.delete(@backup_file)
    log_verbose "✓ Backup file cleaned up"
  rescue StandardError => e
    log_error "Failed to cleanup backup: #{e.message}"
  end

  def log_info(message)
    puts "ℹ️  #{message}"
  end

  def log_success(message)
    puts "✅ #{message}"
  end

  def log_warning(message)
    puts "⚠️  #{message}"
  end

  def log_error(message)
    warn "❌ #{message}"
  end

  def log_verbose(message)
    puts "🔍 #{message}" if @options[:verbose]
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  updater = FormulaUpdater.new
  exit_code = updater.run(ARGV)
  exit exit_code
end