# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [v0.1.34] - 2025-08-28

### Added
- Comprehensive shell completion system for bash, zsh, and fish
- Dynamic completion for device IDs, IP addresses, and ports
- Intelligent command-aware argument completion
- Homebrew automatic completion installation and configuration

### Improved
- Enhanced CLI usability with tab completion support
- Better development experience with shell integration


## [v0.1.26] - 2025-08-22

### Added
- **System Extension Bundle Distribution**: Release workflow now builds and distributes system extension bundles
  - Builds USBIPDSystemExtension target explicitly in release workflow
  - Creates proper system extension bundle structure with Info.plist
  - Applies code signing to system extension bundle
  - Includes system extension bundle in release artifacts as compressed tar.gz
  - Generates checksums for both CLI binary and system extension
  - Updates Homebrew metadata to include system extension download URLs and checksums
  - Enhances release notes with system extension installation instructions

### Fixed
- **Homebrew System Extension Support**: Fixed "System Extension Status: Not Available" error for Homebrew users
  - System extension bundle now properly distributed with releases
  - Homebrew formula can install complete functionality including system extensions
  - Users can now successfully run `sudo usbipd install-system-extension`

## [v0.1.19] - 2025-08-21

### Fixed
- **Test Compilation**: Fixed duplicate BundleSearchResult struct causing compilation ambiguity
  - Removed duplicate struct definition in test file
  - Now uses internal struct from main source file

## [v0.0.17] - 2025-08-21

### Fixed
- **Release Automation**: Complete resolution of GitHub Actions workflow automation issues
  - Fixed critical YAML syntax errors preventing workflow execution
  - Resolved conditional logic in job dependencies
  - Fixed GitHub Actions context variable usage in shell environments
  - Restored proper tag-triggered releases vs branch push filtering
  - Enabled manual workflow_dispatch testing with parameter validation

### Improved
- Enhanced error handling in release workflows
- Improved homebrew-releaser integration reliability
- Better validation of release triggers and conditions

## [v0.0.14] - 2025-08-21

### Added
- **Homebrew Releaser Migration**: Complete migration from webhook system to homebrew-releaser GitHub Action
  - Automated homebrew tap management with homebrew-releaser action
  - Comprehensive post-migration monitoring and validation
  - End-to-end release automation with artifact management
  - Rollback procedures and validation scripts
  - Enhanced documentation and troubleshooting guides

### Changed
- Updated release workflows to use homebrew-releaser action
- Improved homebrew tap repository management
- Enhanced release monitoring and validation

### Removed
- Legacy webhook system for homebrew tap management

## [v0.0.6] - 2025-08-18

### Added
- **Complete System Extension Installation Framework**: Comprehensive system extension lifecycle management
  - Advanced installation orchestration with automatic and manual installation modes
  - Intelligent installation verification and validation system
  - Service lifecycle management with recovery and fallback mechanisms
  - Enhanced diagnostic capabilities for troubleshooting installation issues
- **Production-Ready Installation Workflows**: End-to-end system extension deployment
  - Automated installation process for developer environments
  - Manual installation guidance with step-by-step user instructions
  - Cross-platform compatibility validation (Intel, Apple Silicon, Universal)
  - Installation status monitoring with real-time progress reporting
- **Enhanced CLI Commands and Diagnostics**: Comprehensive command-line interface
  - New `install-system-extension` command for manual installation
  - Advanced `diagnose` command with system health checks
  - Installation verification and status reporting capabilities
  - Interactive troubleshooting and guidance system

### Fixed
- **Critical USB/IP Protocol Issues**: Resolved fatal crashes and protocol errors
  - Fixed USB/IP device list request command encoding (0x05 → 0x8005)
  - Resolved "Index out of range" crashes in integration tests
  - Improved timing for asynchronous notification processing
  - Enhanced error handling for network communication failures
- **Test Infrastructure Stability**: Comprehensive test suite improvements
  - Fixed critical integration test failures affecting production validation
  - Improved mock device simulation and timing reliability
  - Enhanced test environment setup and teardown procedures
  - Resolved Swift concurrency compliance issues
- **System Extension Bundle Detection**: Enhanced bundle management
  - Improved bundle detection and validation logic
  - Fixed bundle path resolution in various installation scenarios
  - Enhanced error handling for bundle creation and management
  - Better compatibility with different macOS versions and architectures

### Changed
- **Installation Architecture**: Streamlined and consolidated installation process
  - Simplified installation workflow with fewer user interaction points
  - Improved error recovery and fallback mechanisms
  - Enhanced logging and diagnostic information collection
  - Better integration with macOS System Extension APIs
- **Test Infrastructure**: Modernized testing approach
  - Consolidated test environments (development, CI, production)
  - Improved QEMU integration testing infrastructure
  - Enhanced mock systems for reliable automated testing
  - Streamlined CI/CD pipeline for faster validation

### Security
- **Enhanced System Extension Security**: Improved security validation
  - Strengthened code signing and entitlement validation
  - Enhanced installation verification to prevent tampering
  - Improved system permission management and validation
  - Better isolation and sandboxing of system extension components

### Performance
- **Optimized Installation Process**: Faster and more reliable installation
  - Reduced installation time through parallel processing
  - Improved resource utilization during installation
  - Enhanced memory management and cleanup procedures
  - Better error recovery without requiring system restarts

## [v0.0.4] - 2025-08-18

### Added
- **Homebrew System Extension Integration**: Complete end-to-end System Extension support for Homebrew installations
  - Automatic System Extension bundle creation during `brew install` process
  - Intelligent installation automation with developer mode detection
  - Manual installation fallback with guided user instructions
  - Cross-platform compatibility validation (Intel x86_64, Apple Silicon ARM64, Universal)
  - macOS version compatibility checking (macOS 11.0+)
- **Enhanced Installation Automation**
  - Automatic System Extension installation in developer mode environments
  - Manual installation script generation for standard environments
  - User guidance and troubleshooting documentation
  - Installation status monitoring and progress reporting
- **Comprehensive Error Handling and Recovery**
  - Structured error categorization and handling framework
  - Automatic recovery strategies for common installation failures
  - Diagnostic information collection for troubleshooting
  - Environment-specific validation and setup verification
- **Advanced Testing Infrastructure**
  - Complete end-to-end Homebrew workflow testing
  - QEMU integration testing for USB/IP protocol validation
  - Multi-environment test suite (development, CI, production)
  - Comprehensive compatibility testing across architectures and macOS versions

### Fixed
- **CI/CD Pipeline Reliability**
  - Resolved GitHub Actions workflow parameter mismatches
  - Fixed SwiftLint strict mode violations (31 violations resolved)
  - Corrected test discovery and execution in CI environments
  - Improved code quality with comprehensive linting compliance
- **System Extension Bundle Creation**
  - Fixed bundle structure validation and code signing integration
  - Resolved duplicate type definitions and build conflicts
  - Corrected Info.plist generation and entitlements configuration
- **Build System Improvements**
  - Enhanced Swift Package Manager integration
  - Improved dependency resolution and caching
  - Fixed cross-compilation issues for Universal binaries

### Changed
- **Test Architecture Refactoring**
  - Reorganized test helper functions to prevent XCTest discovery conflicts
  - Improved test naming conventions (test* → validate* for helpers)
  - Enhanced test execution performance and reliability
- **Documentation and Code Quality**
  - Comprehensive spec-driven development documentation
  - Improved code commenting and inline documentation
  - Enhanced error messages and user-facing guidance

### Technical Details
- System Extension bundle creation with proper macOS bundle structure
- CFBundlePackageType correctly set to "SYSX" for System Extension identification
- Automated code signing integration for notarization-ready bundles
- Environment detection for development vs. production installation workflows
- QEMU-based protocol validation for comprehensive testing coverage

## [v0.0.3] - 2025-08-16

### Added
- Uploaded certs for code signing

## [v0.0.2] - 2025-08-16

### Added
- Improved System Extension installation process

## [v0.0.1] - 2025-08-16

### Added
- Initial release

