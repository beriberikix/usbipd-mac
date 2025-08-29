# Tasks Document

- [x] 1. Create feature branch for completion installation refactor
  - Command: `git checkout -b feature/completion-installation-refactor`
  - Ensure clean working directory before branching
  - Purpose: Follow established git workflow from steering documents
  - _Leverage: existing git workflow patterns_
  - _Requirements: Git workflow compliance_

- [x] 2. Create UserDirectoryResolver component in Sources/USBIPDCore/CLI/UserDirectoryResolver.swift
  - File: Sources/USBIPDCore/CLI/UserDirectoryResolver.swift
  - Define directory resolution methods for each shell type (bash, zsh, fish)
  - Add directory validation and creation utilities
  - Purpose: Centralize user completion directory management logic
  - _Leverage: Sources/USBIPDCore/CLI/CompletionWriter.swift directory validation patterns, Sources/Common/Logger.swift_
  - _Requirements: 1.1, 1.2, 1.5_

- [x] 3. Create CompletionInstaller service in Sources/USBIPDCore/CLI/CompletionInstaller.swift
  - File: Sources/USBIPDCore/CLI/CompletionInstaller.swift
  - Implement install, uninstall, and status methods
  - Add comprehensive error handling and rollback logic
  - Purpose: Provide core installation functionality for completion files
  - _Leverage: Sources/USBIPDCore/CLI/CompletionWriter.swift, Sources/USBIPDCore/CLI/CompletionExtractor.swift, Sources/Common/Logger.swift_
  - _Requirements: 1.1, 1.2, 1.3_

- [x] 4. Define completion installation data models in Sources/USBIPDCore/CLI/CompletionModels.swift
  - File: Sources/USBIPDCore/CLI/CompletionModels.swift (extend existing)
  - Add CompletionInstallSummary, CompletionUninstallSummary, CompletionStatusSummary models
  - Add CompletionFileInfo and CompletionShellStatus structures
  - Purpose: Provide type-safe data structures for installation operations
  - _Leverage: existing CompletionData structures in Sources/USBIPDCore/CLI/CompletionModels.swift_
  - _Requirements: 1.1, 1.2, 1.3_

- [x] 5. Git commit: Core completion installation services
  - Command: `git add Sources/USBIPDCore/CLI/ && git commit -m "feat: add core completion installation services

- CompletionInstaller: install, uninstall, status functionality
- UserDirectoryResolver: shell-specific directory resolution
- Extended CompletionModels with installation data structures

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"`
  - Purpose: Commit core service layer changes following established commit message format
  - _Leverage: existing git commit patterns from steering documents_
  - _Requirements: Git workflow compliance_

- [x] 6. Extend CompletionAction enum in Sources/USBIPDCLI/CompletionCommand.swift
  - File: Sources/USBIPDCLI/CompletionCommand.swift (modify existing)
  - Add install, uninstall, status cases to CompletionAction enum
  - Update argument parsing to handle new actions
  - Purpose: Integrate new actions into existing command dispatch system
  - _Leverage: existing CompletionAction enum and parseArguments method_
  - _Requirements: 1.1, 1.2, 1.3_

- [x] 7. Implement executeInstall method in Sources/USBIPDCLI/CompletionCommand.swift
  - File: Sources/USBIPDCLI/CompletionCommand.swift (continue from task 6)
  - Add executeInstall method following existing action patterns
  - Handle shell filtering and user feedback
  - Purpose: Provide CLI interface for completion installation
  - _Leverage: existing executeGenerate pattern, Sources/USBIPDCore/CLI/CompletionInstaller.swift_
  - _Requirements: 1.1, 1.4_

- [x] 8. Implement executeUninstall method in Sources/USBIPDCLI/CompletionCommand.swift
  - File: Sources/USBIPDCLI/CompletionCommand.swift (continue from task 7)
  - Add executeUninstall method with confirmation prompts
  - Handle partial removal scenarios and error reporting
  - Purpose: Provide CLI interface for completion removal
  - _Leverage: existing action patterns, Sources/USBIPDCore/CLI/CompletionInstaller.swift_
  - _Requirements: 1.2_

- [x] 9. Implement executeStatus method in Sources/USBIPDCLI/CompletionCommand.swift
  - File: Sources/USBIPDCLI/CompletionCommand.swift (continue from task 8)
  - Add executeStatus method with detailed shell status reporting
  - Include up-to-date validation and file information
  - Purpose: Provide CLI interface for completion status checking
  - _Leverage: existing action patterns, Sources/USBIPDCore/CLI/CompletionInstaller.swift_
  - _Requirements: 1.3_

- [x] 10. Update CompletionCommand action dispatch in Sources/USBIPDCLI/CompletionCommand.swift
  - File: Sources/USBIPDCLI/CompletionCommand.swift (continue from task 9)
  - Add new action cases to existing switch statement in execute method
  - Initialize CompletionInstaller dependency in CompletionCommand initializer
  - Purpose: Complete integration of new actions into command execution flow
  - _Leverage: existing action switch pattern in execute method_
  - _Requirements: 1.1, 1.2, 1.3_

- [x] 11. Update completion command help text in Sources/USBIPDCLI/CompletionCommand.swift
  - File: Sources/USBIPDCLI/CompletionCommand.swift (continue from task 10)
  - Update printHelp method to include install, uninstall, status actions
  - Add usage examples for new subcommands
  - Purpose: Provide comprehensive help information for all completion functionality
  - _Leverage: existing printHelp method structure_
  - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 12. Git commit: CLI interface implementation
  - Command: `git add Sources/USBIPDCLI/ && git commit -m "feat: implement completion install/uninstall/status CLI commands

- Extended CompletionAction enum with install, uninstall, status
- Added executeInstall, executeUninstall, executeStatus methods
- Updated help text with new subcommand documentation
- Integrated with existing CLI command dispatch architecture

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"`
  - Purpose: Commit CLI layer changes following established commit message format
  - _Leverage: existing git commit patterns from steering documents_
  - _Requirements: Git workflow compliance_

- [x] 13. Create unit tests for UserDirectoryResolver in Tests/DevelopmentTests/CLI/UserDirectoryResolverTests.swift
  - File: Tests/DevelopmentTests/CLI/UserDirectoryResolverTests.swift
  - Test directory resolution for all supported shells
  - Test error handling for invalid directories and permissions
  - Purpose: Ensure reliable directory resolution across shell environments
  - _Leverage: Tests/SharedUtilities/TestFixtures.swift, existing CLI test patterns_
  - _Requirements: 1.1, 1.5_

- [x] 14. Create unit tests for CompletionInstaller in Tests/DevelopmentTests/CLI/CompletionInstallerTests.swift
  - File: Tests/DevelopmentTests/CLI/CompletionInstallerTests.swift
  - Test install, uninstall, and status operations with mocked file system
  - Test error scenarios and rollback mechanisms
  - Purpose: Ensure installation reliability and proper error handling
  - _Leverage: Tests/TestMocks/FileSystemMocks.swift, Tests/SharedUtilities/TestAssertions.swift_
  - _Requirements: 1.1, 1.2, 1.3_

- [x] 15. Create integration tests for completion installation in Tests/CITests/Integration/CompletionInstallationTests.swift
  - File: Tests/CITests/Integration/CompletionInstallationTests.swift
  - Test end-to-end installation workflows in temporary directories
  - Test cross-shell compatibility and file validation
  - Purpose: Validate complete installation process in controlled environment
  - _Leverage: Tests/SharedUtilities/TemporaryDirectoryManager.swift, existing integration test patterns_
  - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 16. Git commit: Test implementation
  - Command: `git add Tests/ && git commit -m "test: add comprehensive tests for completion installation

- Unit tests for UserDirectoryResolver and CompletionInstaller
- Integration tests for end-to-end installation workflows
- Mock file system support for reliable testing
- Cross-shell compatibility validation

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"`
  - Purpose: Commit test implementation following established commit message format
  - _Leverage: existing git commit patterns from steering documents_
  - _Requirements: Git workflow compliance_

- [x] 17. Run development test suite to validate implementation
  - Command: `./Scripts/run-development-tests.sh`
  - Ensure all new tests pass and existing tests remain unbroken
  - Fix any test failures before proceeding
  - Purpose: Validate implementation in development environment
  - _Leverage: existing development test environment_
  - _Requirements: All core functionality_

- [x] 18. Create production validation tests in Tests/ProductionTests/Validation/CompletionInstallationValidationTests.swift
  - File: Tests/ProductionTests/Validation/CompletionInstallationValidationTests.swift
  - Test installation in real user environment with actual shell directories
  - Validate installed completions work with actual shell completion systems
  - Purpose: Ensure production readiness and real-world functionality
  - _Leverage: Tests/SharedUtilities/ShellTestUtils.swift, production test environment patterns_
  - _Requirements: All_

- [x] 19. Run full CI test suite to ensure compatibility
  - Command: `./Scripts/run-ci-tests.sh`
  - Validate no regressions in existing functionality
  - Ensure new functionality works in CI environment
  - Purpose: Pre-validate CI compatibility before PR
  - _Leverage: existing CI test environment_
  - _Requirements: All_

- [x] 20. Update Homebrew formula to remove usbipd-install-completions executable
  - File: Formula/usbipd-mac.rb (in separate homebrew-usbipd-mac repository)
  - Remove usbipd-install-completions from installed binaries
  - Update post-install message to use usbipd completion install
  - Purpose: Complete transition away from separate executable approach
  - _Leverage: existing formula structure and post-install patterns_
  - _Requirements: 1.4, 1.5_

- [x] 21. Git commit: Distribution and compatibility updates
  - Command: `git add Formula/ Sources/USBIPDCLI/ && git commit -m "feat: update distribution for completion refactor

- Updated Homebrew formula to remove separate executable
- Updated post-install instructions to use new commands

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"`
  - Purpose: Commit distribution changes following established commit message format
  - _Leverage: existing git commit patterns from steering documents_
  - _Requirements: Git workflow compliance_

- [x] 22. Run SwiftLint to ensure code quality standards
  - Command: `swiftlint lint --strict`
  - Fix any linting violations according to project standards
  - Ensure compliance with established code style
  - Purpose: Maintain code quality per steering document requirements
  - _Leverage: existing SwiftLint configuration_
  - _Requirements: Code quality compliance_

- [x] 23. Run production test suite for final validation
  - Command: `./Scripts/run-production-tests.sh`
  - Validate complete functionality in production-like environment
  - Ensure all edge cases and real-world scenarios work correctly
  - Purpose: Final validation before PR submission
  - _Leverage: existing production test environment_
  - _Requirements: All_

- [x] 24. Create pull request and ensure CI passes
  - Command: `git push -u origin feature/completion-installation-refactor && gh pr create --title "feat: refactor completion installation to CLI subcommands" --body "$(cat <<'EOF'
## Summary
- Refactors shell completion installation from separate `usbipd-install-completions` executable to proper `usbipd completion install/uninstall/status` subcommands
- Improves discoverability and maintainability by consolidating functionality into main CLI
- Maintains backward compatibility during transition period

## Test plan
- [x] Unit tests for UserDirectoryResolver and CompletionInstaller
- [x] Integration tests for end-to-end installation workflows
- [x] Production validation with real shell environments
- [x] SwiftLint compliance validation
- [x] All existing tests continue to pass

🤖 Generated with [Claude Code](https://claude.ai/code)
EOF
)"`
  - Monitor CI pipeline and address any failures
  - Ensure all automated checks pass before requesting review
  - Purpose: Follow established git workflow for feature integration
  - _Leverage: existing CI pipeline and PR processes_
  - _Requirements: Git workflow compliance, All functional requirements_