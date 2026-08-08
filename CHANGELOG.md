# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.5.3] - 2026-08-08

### Fixed — the CLI was unusable to read

A plain `usbipd list` printed roughly forty lines of debug logging around three lines
of output. Every component constructs its own `Logger` with a hardcoded level — 27 at
`.info`, 3 at `.debug` — so `ServerConfig.logLevel` governed nothing. `Logger` now has a
process-wide floor defaulting to `.warning`, which wins where it is stricter. The daemon
raises it to `.info`, since its output goes to a log file, and `USBIPD_LOG_LEVEL`
overrides both.

### Fixed — `usbipd -v` reported the wrong build

A Homebrew-installed release binary printed `Build: Development`, because `main.swift`
emitted that literal. A correct implementation existed in `CommandLineParser` but was
never reached, since `main.swift` intercepts `-v` first. Both now read one value.

### Fixed — the CLI hunted for a System Extension on every command

The bundle detector walked the filesystem on every invocation, including the
developer's own `.build` directory: an installed binary was scanning a source tree it
found there and adopting a debug bundle from it. The manager was also started each
time, restoring claim state for a subsystem that cannot be activated from a Homebrew
prefix. Neither now happens, and `usbipd status` no longer instructs users to install a
System Extension they cannot install.

### Fixed — `usbipd completion` wrote files when given no verb

The action defaulted to `generate`, whose output directory defaults to the working
directory, so a bare `usbipd completion` silently wrote three completion scripts
wherever the user was standing. It now prints usage.

## [v0.5.2] - 2026-08-07

### Added — Intel Macs are supported again

Releases through v0.5.1 shipped an arm64-only binary, because the release workflow ran
a plain `swift build` on an Apple silicon runner. Installing on an Intel Mac succeeded
and then failed with `Bad CPU type in executable` (#32).

The build now produces both architectures and splits them with `lipo`, publishing
`usbipd-<version>-macos-arm64` and `usbipd-<version>-macos-x86_64`. The formula selects
with `on_arm`/`on_intel`, so each user downloads one artifact of about 5.4 MB — slightly
smaller than the arm64-only build, rather than the 10.8 MB a universal binary would
cost everyone. Each slice is signed separately, since `lipo -thin` strips the signature.

## [v0.5.1] - 2026-08-07

### Fixed — control transfers were broken in release builds only

`performControlTransfer` returned a pointer out of `setupPacket.withUnsafeBytes`,
which only guarantees it inside the closure. Every subsequent read was of freed
memory. Debug builds happened to leave the bytes intact, so all prior validation
passed; optimised builds did not, so `bmRequestType`, `bRequest`, `wValue`, `wIndex`
and `wLength` became garbage, the device received a malformed request, and the pipe
stalled — `kIOUSBPipeStalled`, reaching clients as EPROTO.

This affected **v0.5.0 as shipped**: control transfers are how a client enumerates a
device, so attaching from Linux would fail against the released binary even though bulk
transfers worked. Found by testing the Homebrew-installed artifact rather than a local
debug build.

## [v0.5.0] - 2026-08-06

First release in which the software does what it claims. Every prior release shipped a
transfer path that had never moved data, and a `bind` that recorded devices without
serving them. Those releases have been deleted rather than left to mislead.

The version number also means something now: it was hardcoded as "0.1.0" in three
separate print statements, so every previous release reported 0.1.0 regardless of its
tag.

### Fixed — USB transfers now reach real hardware

The transfer path had never moved data. Several defects sat between a client
request and the device, each hiding the next.

- `ReadPipeTO`'s size argument is in/out — buffer capacity in, bytes read out — and was
  initialised to 0 and never set. IOKit was told the buffer could hold nothing, so any
  packet the device sent overran it. **Every IN transfer on the bulk and interrupt paths
  failed this way.**
- Transfer type was guessed from the request's interval field. USB/IP carries no
  transfer type, so it now comes from the device via `GetPipeProperties`. A J-Link
  declares `bInterval 1` on both of its *bulk* pipes, so the guess routed bulk traffic
  to the interrupt path.
- IOKit addresses pipes by a 1-based index into the interface, not by endpoint number.
  Endpoint discovery is now implemented and the index looked up.
- Direction was taken from bit 7 of the endpoint address, which a conforming client
  leaves clear because it sends direction in its own field.
- `USBSubmitProcessor` fabricated a `0000:0000` device instead of resolving the devid,
  so every lookup failed with ENODEV.
- 33 escaped string interpolations in `USBDeviceCommunicatorImplementation` — the one in
  `deviceIdentifier(for:)` gave every device the same literal key, so no claim matched.

Verified with probe-rs driving a J-Link from a Linux client over USB/IP, reading the
probe's VTref exactly as it does connected directly.

### Fixed — the bind allow-list is enforced

`bind` wrote devices to `allowedDevices` and nothing ever read it back. The server
advertised **every** USB device on the machine and served transfers on any of them,
bound or not. `isDeviceAllowed` also returned true for an empty list, so a fresh
install offered everything. Both are fixed; sharing is opt-in.

### Added — `bind` refuses devices something else owns

Previously it allow-listed anything and failed later at transfer time. It now reads
ownership from the IORegistry and refuses with an explanation naming the owner,
distinguishing a kernel driver (needs a DriverKit entitlement) from a userspace holder
(quit the app).

### Added — configuration settings are honoured

`maxUSBBufferSize`, `usbOperationTimeout`, `maxTotalConcurrentRequests`,
`maxPendingURBsPerDevice`, `maxConnections` and `connectionTimeout` all persisted and
validated their own ranges while nothing read them. They now apply. `maxUSBBufferSize`
matters most: `IOKitUSBInterface` allocated `Int(bufferLength)` straight from a
wire-supplied `UInt32`. `autoBindDevices` was removed rather than implemented, being
the opposite of the opt-in model.

### Fixed — transfers reported bytes they did not have

A timed-out IN transfer answered with `actualLength` set to the buffer capacity and no
payload, because that field is primed for `ReadPipeTO`'s in/out contract and IOKit does
not reset it when nothing is read. A client reading that many bytes would
desynchronise. Zeroed on every non-success path, for bulk and interrupt.

The default transfer timeout was also raised from 5000 ms to 60000 ms. At five seconds
any merely idle IN endpoint produced ETIMEDOUT, and `adb` gave up on its first read.
Both were found by testing against an Android device.

### Fixed — miscellaneous

- Bulk transfers apply a timeout; they used `ReadPipe`/`WritePipe`, which block forever
- `kIOUSBTransactionTimeout` maps to ETIMEDOUT rather than falling through to EPROTO
- A `defer` in a registry loop released the entry the next iteration was about to read
- `CommandHandlerError` was re-wrapped in itself, doubling error prefixes
- Data races in `USBSubmitProcessor` (concurrent-queue writes without `.barrier`)

### Removed

- `attach` and `detach`, which macOS cannot implement — that is a client-side operation
- `install-system-extension`, which could not succeed from a Homebrew prefix, and
  `diagnose`, which did not complete in 300 seconds. Both were registered but absent
  from `usbipd --help`
- The `.kiro` and `.gemini` directories
- `URBTracker`, `DeviceMonitor`, the global logging functions, and five other
  mechanisms that had tests but no production callers, dropping 42 tests that covered
  code the daemon never reached
- Two message validators with no callers anywhere, one of which contained a check that
  could never fire (`endpoint & 0x0F > 15`)
- ~17,800 lines of test targets that no target compiled and that had never run

### Added — MIT LICENSE

The README had claimed MIT while no LICENSE file existed, leaving the terms of
distribution unstated.

### Measured

- Seizing an interface does **not** take it from a kernel driver:
  `USBInterfaceOpenSeize` returns the same `kIOReturnExclusiveAccess` as a plain open.
  Neither unmounting nor ejecting releases a device either. Measured against mass
  storage, HID and a webcam.
- `com.apple.security.device.usb` is an App Sandbox entitlement and grants nothing
  here; the DriverKit transport entitlements are what gate this.

### Known limitations

- **Clients whose protocol keys off connection or reset events may not work**, even on
  a device that claims cleanly. `adb` reports an otherwise-working Pixel `offline`: the
  phone announces itself once per USB connection and macOS already received that
  announcement, and attaching from a client causes no bus reset the phone can observe.
  Request/response devices are unaffected.
- **UNLINK does not abort an in-flight read.** It answers `RET_UNLINK` immediately, but
  the transfer is only reclaimed when its own timeout expires. This is why the timeout
  cannot be removed in favour of unlimited waits.
- **`bind` does not affect a running daemon**, which reads the allow-list only at
  startup.

- Interrupt endpoints are unverified against hardware
- Isochronous is structurally incomplete: alternate settings are never selected and
  pipes are discovered once at open, so a UVC device's isochronous endpoints never appear
- The System Extension subsystem is quarantined and no shipping path activates it

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

