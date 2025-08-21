# Homebrew Troubleshooting Guide

This guide provides solutions to common issues encountered when installing and using usbipd-mac through Homebrew.

## Table of Contents

- [Installation Issues](#installation-issues)
- [Service Management Problems](#service-management-problems)
- [System Extension Issues](#system-extension-issues)
- [Uninstallation and Cleanup](#uninstallation-and-cleanup)
- [Version Management](#version-management)
- [Performance Issues](#performance-issues)
- [External Tap Repository Issues](#external-tap-repository-issues)
- [Advanced Debugging](#advanced-debugging)

## Installation Issues

### Formula Installation Failures

#### Problem: "No available formula with name" error
```bash
Error: No available formula with name "usbipd-mac".
```

**Solution:**
1. Ensure you've added the tap first:
   ```bash
   brew tap beriberikix/usbipd-mac
   ```
2. Update Homebrew to ensure latest formula availability:
   ```bash
   brew update
   ```
3. Verify the tap was added successfully:
   ```bash
   brew tap | grep beriberikix/usbipd-mac
   ```

#### Problem: Build failures during installation
```bash
==> Installing usbipd-mac from beriberikix/usbipd-mac
==> swift build --configuration release
Error: Build failed
```

**Solution:**
1. Check macOS version compatibility (requires macOS 11.0+):
   ```bash
   sw_vers
   ```
2. Verify Xcode command line tools are installed:
   ```bash
   xcode-select --install
   ```
3. Ensure sufficient disk space (at least 500MB free)
4. Try building from source with verbose output:
   ```bash
   brew install --build-from-source --verbose usbipd-mac
   ```

#### Problem: Permission denied errors during installation
```bash
Error: Permission denied @ rb_file_s_symlink
```

**Solution:**
1. Fix Homebrew permissions:
   ```bash
   sudo chown -R $(whoami) $(brew --prefix)/*
   ```
2. Re-run installation:
   ```bash
   brew install usbipd-mac
   ```

### Dependency Issues

#### Problem: Swift version incompatibility
```bash
Error: Swift version 5.5 or later is required
```

**Solution:**
1. Update Xcode from the App Store
2. Update command line tools:
   ```bash
   sudo xcode-select --install
   ```
3. Verify Swift version:
   ```bash
   swift --version
   ```

## Service Management Problems

### Homebrew Services Integration

#### Problem: Service fails to start
```bash
$ brew services start usbipd-mac
Error: Service `usbipd-mac` failed to start
```

**Solution:**
1. Check service status:
   ```bash
   brew services list | grep usbipd-mac
   ```
2. View service logs:
   ```bash
   tail -f $(brew --prefix)/var/log/usbipd-mac.log
   ```
3. Verify service file permissions:
   ```bash
   ls -la $(brew --prefix)/var/log/
   ```
4. Try manual service management:
   ```bash
   sudo launchctl load $(brew --prefix)/Library/LaunchDaemons/homebrew.mxcl.usbipd-mac.plist
   ```

#### Problem: Permission denied when starting service
```bash
Error: Permission denied - /usr/local/var/log/usbipd-mac.log
```

**Solution:**
1. Create log directory with proper permissions:
   ```bash
   sudo mkdir -p $(brew --prefix)/var/log
   sudo chown $(whoami) $(brew --prefix)/var/log
   ```
2. Restart the service:
   ```bash
   brew services restart usbipd-mac
   ```

### Service Configuration Issues

#### Problem: Service starts but doesn't accept connections
**Solution:**
1. Check if the service is binding to the correct port:
   ```bash
   lsof -i :3240
   ```
2. Verify firewall settings:
   ```bash
   sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
   ```
3. Check System Extension status (see [System Extension Issues](#system-extension-issues))

## System Extension Issues

### System Extension Approval

#### Problem: System Extension blocked after Homebrew installation
```bash
System Extension Blocked
"usbipd-mac" will damage your computer. You should move it to the Trash.
```

**Solution:**
1. Open System Preferences → Security & Privacy
2. In the General tab, click "Allow" next to the blocked system extension
3. If no "Allow" button appears, try:
   ```bash
   sudo systemextensionsctl reset
   brew services restart usbipd-mac
   ```

#### Problem: System Extension fails to load
```bash
Error: Failed to load system extension
OSSystemExtensionErrorDomain Code=8
```

**Solution:**
1. Check SIP (System Integrity Protection) status:
   ```bash
   csrutil status
   ```
2. If SIP is enabled and blocking extensions, disable it temporarily:
   - Restart in Recovery Mode (Intel: ⌘R, Apple Silicon: Hold power button)
   - Open Terminal and run: `csrutil disable`
   - Restart normally and retry installation
   - Re-enable SIP: `csrutil enable`

3. Clear system extension cache:
   ```bash
   sudo systemextensionsctl reset
   sudo reboot
   ```

### System Extension Permissions

#### Problem: System Extension lacks necessary permissions
**Solution:**
1. Grant Full Disk Access to usbipd-mac:
   - System Preferences → Security & Privacy → Privacy → Full Disk Access
   - Add `/usr/local/bin/usbipd` (or `$(brew --prefix)/bin/usbipd`)

2. Check and grant USB device access:
   - Some devices may require additional permissions in Security & Privacy

## Uninstallation and Cleanup

### Complete Uninstallation

#### Clean removal of usbipd-mac via Homebrew
```bash
# Stop the service
brew services stop usbipd-mac

# Uninstall the package
brew uninstall usbipd-mac

# Remove the tap (optional)
brew untap usbipd-mac/tap

# Clean up system extension
sudo systemextensionsctl uninstall [TEAM_ID] com.usbipd-mac.SystemExtension
```

#### Remove leftover files
```bash
# Remove log files
sudo rm -rf $(brew --prefix)/var/log/usbipd-mac*

# Remove configuration files (if any)
sudo rm -rf ~/Library/Preferences/com.usbipd-mac.*

# Remove application support files
sudo rm -rf ~/Library/Application\ Support/usbipd-mac
```

### Service Cleanup

#### Problem: Service remains after uninstallation
```bash
$ brew services list | grep usbipd-mac
usbipd-mac stopped brown /Users/user/Library/LaunchAgents/homebrew.mxcl.usbipd-mac.plist
```

**Solution:**
```bash
# Unload the service
launchctl unload ~/Library/LaunchAgents/homebrew.mxcl.usbipd-mac.plist

# Remove the plist file
rm ~/Library/LaunchAgents/homebrew.mxcl.usbipd-mac.plist

# For system-wide services
sudo launchctl unload /Library/LaunchDaemons/homebrew.mxcl.usbipd-mac.plist
sudo rm /Library/LaunchDaemons/homebrew.mxcl.usbipd-mac.plist
```

## Version Management

### Version Pinning

#### Pin to specific version to prevent auto-updates
```bash
# Install specific version
brew install usbipd-mac@1.0.0

# Pin current version
brew pin usbipd-mac

# List pinned packages
brew list --pinned
```

#### Unpin to allow updates
```bash
brew unpin usbipd-mac
```

### Rollback Procedures

#### Problem: New version breaks functionality
**Solution:**
1. Check available versions:
   ```bash
   brew search usbipd-mac
   ```

2. Uninstall current version:
   ```bash
   brew services stop usbipd-mac
   brew uninstall usbipd-mac
   ```

3. Install previous version:
   ```bash
   brew install usbipd-mac@[VERSION]
   ```

4. If specific version not available, install from commit:
   ```bash
   brew install https://raw.githubusercontent.com/beriberikix/homebrew-usbipd-mac/[COMMIT_HASH]/Formula/usbipd-mac.rb
   ```

### Upgrade Issues

#### Problem: Upgrade fails with dependency conflicts
```bash
Error: Cannot install usbipd-mac because conflicting formulae are installed
```

**Solution:**
1. Update Homebrew:
   ```bash
   brew update
   ```

2. Clean up outdated dependencies:
   ```bash
   brew cleanup
   brew doctor
   ```

3. Force reinstall if necessary:
   ```bash
   brew reinstall usbipd-mac
   ```

## Performance Issues

### Slow Installation

#### Problem: Installation takes too long
**Solution:**
1. Use pre-built bottles instead of building from source:
   ```bash
   brew install --force-bottle usbipd-mac
   ```

2. Clear Homebrew cache if corrupted:
   ```bash
   brew cleanup --prune=all
   ```

3. Check network connectivity and try different mirror:
   ```bash
   export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.aliyun.com/homebrew/homebrew-bottles"
   brew install usbipd-mac
   ```

### Runtime Performance

#### Problem: High CPU usage or memory consumption
**Solution:**
1. Check service configuration:
   ```bash
   brew services list usbipd-mac
   ```

2. Monitor resource usage:
   ```bash
   top -pid $(pgrep usbipd)
   ```

3. Restart service to clear potential memory leaks:
   ```bash
   brew services restart usbipd-mac
   ```

## Advanced Debugging

### Diagnostic Information Collection

#### Collect comprehensive system information for bug reports
```bash
# System information
sw_vers
uname -a

# Homebrew environment
brew --version
brew config
brew doctor

# usbipd-mac specific
brew list --versions usbipd-mac
brew services list | grep usbipd-mac

# System Extension status
systemextensionsctl list

# Log files
tail -n 50 $(brew --prefix)/var/log/usbipd-mac.log
tail -n 50 /var/log/system.log | grep usbipd

# Network status
lsof -i :3240
netstat -an | grep 3240
```

### Debug Mode

#### Enable verbose logging for troubleshooting
1. Edit the service configuration to add debug flags:
   ```bash
   brew services stop usbipd-mac
   # Edit $(brew --prefix)/Library/LaunchDaemons/homebrew.mxcl.usbipd-mac.plist
   # Add <string>--verbose</string> to ProgramArguments array
   brew services start usbipd-mac
   ```

2. Monitor debug output:
   ```bash
   tail -f $(brew --prefix)/var/log/usbipd-mac.log
   ```

### Common Environment Issues

#### Problem: Homebrew prefix conflicts
**Solution:**
1. Check Homebrew prefix:
   ```bash
   brew --prefix
   ```

2. If using non-standard prefix, ensure PATH is correct:
   ```bash
   echo 'export PATH="$(brew --prefix)/bin:$PATH"' >> ~/.zshrc
   source ~/.zshrc
   ```

#### Problem: Shell environment issues
**Solution:**
1. Verify shell configuration:
   ```bash
   echo $SHELL
   which brew
   ```

2. Re-initialize Homebrew environment:
   ```bash
   eval "$(/opt/homebrew/bin/brew shellenv)"  # Apple Silicon
   eval "$(/usr/local/bin/brew shellenv)"     # Intel Mac
   ```

## External Tap Repository Issues

This section covers troubleshooting issues specific to the external tap repository architecture that uses homebrew-releaser for automated formula updates.

### Homebrew-Releaser Integration Problems

#### Problem: Formula not updating after new release
```bash
# New release published but formula still shows old version
brew info usbipd-mac
# Shows: usbipd-mac: stable 0.0.8 (bottled)
# Expected: Latest version (e.g., 0.0.9)
```

**Solution:**
1. Force update the tap repository:
   ```bash
   brew untap beriberikix/usbipd-mac
   brew tap beriberikix/usbipd-mac
   brew update
   ```

2. Check if homebrew-releaser action succeeded:
   - Visit: https://github.com/beriberikix/usbipd-mac/actions
   - Look for recent "Production Release" workflow runs
   - Check the "Update Homebrew Formula" step for any failures

3. Verify the tap repository was updated:
   - Visit: https://github.com/beriberikix/homebrew-usbipd-mac/commits/main
   - Look for recent formula update commits from github-actions[bot]

4. If homebrew-releaser failed, re-run the release workflow:
   ```bash
   # Re-run the release workflow which includes homebrew-releaser
   gh workflow run release.yml --repo beriberikix/usbipd-mac -f version=v0.0.9
   ```

### Formula Validation Issues

#### Problem: Formula update fails validation
```
Error: Formula validation failed with critical errors
Ruby syntax: ✓ Passed
Homebrew structure: ✗ Missing required component: Install method
```

**Solution:**
1. Check the tap repository formula template:
   ```bash
   # Clone tap repository to inspect
   git clone https://github.com/beriberikix/homebrew-usbipd-mac.git
   cd homebrew-usbipd-mac
   ruby -c Formula/usbipd-mac.rb
   ```

2. Validate formula structure manually:
   ```bash
   # Check for required components
   grep -E "(class.*Formula|desc|homepage|url|version|sha256|def install)" Formula/usbipd-mac.rb
   ```

3. If template is corrupted, restore from backup:
   ```bash
   # Reset to last working commit
   git log --oneline -10
   git reset --hard [WORKING_COMMIT_HASH]
   git push --force origin main
   ```

4. Test formula installation locally:
   ```bash
   # Test updated formula
   brew install --build-from-source ./Formula/usbipd-mac.rb
   ```

### Homebrew-Releaser Configuration Problems

#### Problem: Homebrew-releaser action fails with configuration errors
```
Error: Formula generation failed: missing required parameter 'install'
```

**Solution:**
1. Check the homebrew-releaser configuration in `.github/workflows/release.yml`:
   ```bash
   # Review the homebrew-releaser step configuration
   grep -A 20 "uses: Justintime50/homebrew-releaser" .github/workflows/release.yml
   ```

2. Verify required parameters are present:
   - `homebrew_owner`: beriberikix
   - `homebrew_tap`: homebrew-usbipd-mac  
   - `formula_folder`: Formula
   - `github_token`: ${{ secrets.HOMEBREW_TAP_TOKEN }}
   - `install`: Installation instructions
   - `test`: Formula test commands

3. Validate the HOMEBREW_TAP_TOKEN secret:
   ```bash
   # Test token permissions (requires token access)
   gh auth status --hostname github.com
   gh repo view beriberikix/homebrew-usbipd-mac --json permissions
   ```

### Recovery Procedures

#### Emergency Formula Update
If homebrew-releaser fails and you need to update the formula immediately:

1. **Manual formula update in tap repository:**
   ```bash
   # Clone tap repository
   git clone https://github.com/beriberikix/homebrew-usbipd-mac.git
   cd homebrew-usbipd-mac
   
   # Update formula manually (check current formula for exact format)
   # Update version and SHA256 in Formula/usbipd-mac.rb
   
   # Validate and commit
   ruby -c Formula/usbipd-mac.rb
   git add Formula/usbipd-mac.rb
   git commit -m "feat: emergency formula update to v0.0.9"
   git push origin main
   ```

2. **Force tap refresh for users:**
   ```bash
   # Users experiencing issues can force refresh
   brew untap beriberikix/usbipd-mac
   brew tap beriberikix/usbipd-mac
   brew install usbipd-mac
   ```

#### Re-run Release Workflow
When homebrew-releaser fails, re-run the entire release workflow:

1. **Via GitHub web interface:**
   - Go to: https://github.com/beriberikix/usbipd-mac/actions/workflows/release.yml
   - Click "Run workflow"
   - Enter version (e.g., v0.0.9)
   - Click "Run workflow"

2. **Via GitHub CLI:**
   ```bash
   gh workflow run release.yml \
     --repo beriberikix/usbipd-mac \
     -f version=v0.0.9
   ```

### Monitoring and Diagnostics

#### Check Repository Health
```bash
# Verify tap repository status
brew tap-info beriberikix/usbipd-mac

# Check recent commits in tap repository
gh repo view beriberikix/homebrew-usbipd-mac --json defaultBranch,updatedAt,pushedAt

# Monitor release workflow runs in main repository
gh run list --repo beriberikix/usbipd-mac --workflow=release.yml --limit 5
```

#### Homebrew-Releaser Debugging
```bash
# Check release workflow logs for homebrew-releaser step
gh run view [RUN_ID] --repo beriberikix/usbipd-mac --log

# Verify tap repository commits from github-actions[bot]
gh api repos/beriberikix/homebrew-usbipd-mac/commits --jq '.[] | select(.author.login == "github-actions[bot]") | {message: .commit.message, date: .commit.author.date}'
```

#### Get Support for Tap Issues
If you encounter persistent issues with the external tap repository:

1. **Check main repository GitHub Actions**: https://github.com/beriberikix/usbipd-mac/actions
2. **Review release workflow logs**: Look for homebrew-releaser step failures
3. **Check tap repository**: Look for successful formula update commits
4. **File issues**: Create issues in the main repository for homebrew-releaser problems

## Getting Additional Help

If the solutions in this guide don't resolve your issue:

1. **Check the main project documentation**: [README.md](../README.md)
2. **Review system extension troubleshooting**: [system-extension-troubleshooting.md](troubleshooting/system-extension-troubleshooting.md)
3. **File a bug report**: Include the diagnostic information from the [Advanced Debugging](#advanced-debugging) section
4. **Community support**: Check existing issues and discussions in the project repository

Remember to include your macOS version, Homebrew version, and the complete error message when seeking help.