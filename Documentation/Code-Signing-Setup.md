# Code Signing Setup Guide

This guide covers the setup and configuration of Apple Developer certificates and code signing for the usbipd-mac project. Proper code signing is essential for macOS System Extensions and distribution through automated release workflows.

## Overview

The usbipd-mac project requires proper code signing for:
- **Main executable** (`usbipd`): Standard application signing
- **System Extension** (`USBIPDSystemExtension`): Requires special entitlements and provisioning
- **QEMUTestServer**: Testing utility with minimal requirements
- **Release artifacts**: Distribution packages and installers

## Apple Developer Certificate Requirements

### Required Certificates

1. **Developer ID Application Certificate**
   - Used for signing the main `usbipd` executable
   - Required for distribution outside the App Store
   - Certificate type: `Developer ID Application: [Your Name] ([Team ID])`

2. **Developer ID Installer Certificate**
   - Used for signing distribution packages
   - Required for creating signed `.pkg` installers
   - Certificate type: `Developer ID Installer: [Your Name] ([Team ID])`

3. **Apple Development Certificate** (Development only)
   - Used during development and testing
   - Required for local System Extension development
   - Certificate type: `Apple Development: [Your Name] ([Team ID])`

### Certificate Installation

1. **Download from Apple Developer Portal**:
   - Log in to [Apple Developer Portal](https://developer.apple.com/account)
   - Navigate to Certificates, Identifiers & Profiles
   - Download and install certificates to macOS Keychain

2. **Verify Installation**:
   ```bash
   # List available signing identities
   security find-identity -v -p codesigning
   
   # Verify specific certificate
   security find-certificate -c "Developer ID Application: [Your Name]"
   ```

## App ID Configuration

### Main Application App ID

Configure App ID for the main application:
- **Bundle ID**: `com.yourteam.usbipd-mac`
- **Description**: USB/IP Device Sharing for macOS
- **Capabilities**:
  - System Extension

### System Extension App ID

Configure App ID for the System Extension:
- **Bundle ID**: `com.yourteam.usbipd-mac.system-extension`
- **Description**: USB/IP System Extension
- **Capabilities**:
  - DriverKit
  - System Extension
  - USB Device Access

## Entitlements Configuration

### Main Application Entitlements (`usbipd.entitlements`)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Allow development and debugging (remove for production) -->
    <key>com.apple.security.get-task-allow</key>
    <false/>
    
    <!-- System Extension installation permission -->
    <key>com.apple.developer.system-extension.install</key>
    <true/>
    
    <!-- USB device access -->
    <key>com.apple.security.device.usb</key>
    <true/>
    
    <!-- Hardened runtime entitlements -->
    <key>com.apple.security.cs.allow-jit</key>
    <false/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <false/>
    <key>com.apple.security.cs.allow-dyld-environment-variables</key>
    <false/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <false/>
</dict>
</plist>
```

### System Extension Entitlements (`Sources/SystemExtension/SystemExtension.entitlements`)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- DriverKit development entitlements -->
    <key>com.apple.developer.driverkit</key>
    <true/>
    <key>com.apple.developer.driverkit.allow-any-userclient-access</key>
    <true/>
    <key>com.apple.developer.driverkit.usb.transport</key>
    <true/>
    
    <!-- System Extension entitlements -->
    <key>com.apple.developer.system-extension.install</key>
    <true/>
    <key>com.apple.developer.system-extension.request</key>
    <true/>
    
    <!-- USB device access -->
    <key>com.apple.security.device.usb</key>
    <true/>
    
    <!-- IOKit user client access -->
    <key>com.apple.security.iokit-user-client-class</key>
    <array>
        <string>IOUSBDeviceUserClientV2</string>
        <string>IOUSBInterfaceUserClientV2</string>
        <string>AppleUSBHostDeviceUserClient</string>
        <string>AppleUSBHostInterfaceUserClient</string>
    </array>
    
    <!-- Endpoint Security for device monitoring -->
    <key>com.apple.developer.endpoint-security.client</key>
    <true/>
</dict>
</plist>
```

## GitHub Secrets Configuration

### Required Secrets for Automated Releases

Configure these secrets in your GitHub repository settings:

#### Certificate and Key Secrets

1. **`DEVELOPER_ID_APPLICATION_CERT_BASE64`**
   - Base64-encoded Developer ID Application certificate (.p12)
   - Generate: `base64 -i certificate.p12 | pbcopy`

2. **`DEVELOPER_ID_APPLICATION_CERT_PASSWORD`**
   - Password for the Developer ID Application certificate

3. **`DEVELOPER_ID_INSTALLER_CERT_BASE64`**
   - Base64-encoded Developer ID Installer certificate (.p12)
   - Generate: `base64 -i installer_certificate.p12 | pbcopy`

4. **`DEVELOPER_ID_INSTALLER_CERT_PASSWORD`**
   - Password for the Developer ID Installer certificate

#### Apple Developer Credentials

5. **`APPLE_DEVELOPER_TEAM_ID`**
   - Your Apple Developer Team ID (10 character alphanumeric)

6. **`APPLE_DEVELOPER_APP_ID`**
   - Bundle ID for the main application (`com.yourteam.usbipd-mac`)

7. **`APPLE_DEVELOPER_SYSTEM_EXTENSION_APP_ID`**
   - Bundle ID for the System Extension (`com.yourteam.usbipd-mac.system-extension`)

#### Notarization Credentials (Optional)

8. **`APPLE_DEVELOPER_ID_EMAIL`**
   - Apple ID email for notarization

9. **`APPLE_DEVELOPER_ID_PASSWORD`**
   - App-specific password for notarization

10. **`APPLE_ASC_PROVIDER`**
    - Apple ASC provider short name (if multiple teams)

#### Repository Dispatch Tokens

11. **`HOMEBREW_TAP_DISPATCH_TOKEN`**
    - GitHub Personal Access Token for triggering repository dispatch events
    - Target repository: `beriberikix/homebrew-usbipd-mac`
    - Required permissions: `repo` scope (for repository dispatch actions)
    - Token rotation: Recommended every 90 days for security
    - **Note**: This is separate from `HOMEBREW_TAP_TOKEN` (used by homebrew-releaser action)

#### Token Purpose Clarification

- **`HOMEBREW_TAP_TOKEN`**: Used by homebrew-releaser GitHub Action for direct formula updates
- **`HOMEBREW_TAP_DISPATCH_TOKEN`**: Used by repository dispatch system for triggering tap repository workflows
- **Migration Note**: During the transition from homebrew-releaser to repository dispatch, both tokens will coexist

### Setting Up Secrets

1. **Export certificates from Keychain**:
   ```bash
   # Export as .p12 file with a secure password
   # Use Keychain Access > Export Items
   ```

2. **Add to GitHub Repository**:
   - Go to repository Settings > Secrets and variables > Actions
   - Add each secret with the exact names listed above

3. **Verify in Workflow**:
   ```yaml
   - name: Setup Code Signing
     env:
       DEVELOPER_ID_CERT_BASE64: ${{ secrets.DEVELOPER_ID_APPLICATION_CERT_BASE64 }}
       DEVELOPER_ID_CERT_PASSWORD: ${{ secrets.DEVELOPER_ID_APPLICATION_CERT_PASSWORD }}
     run: |
       echo "$DEVELOPER_ID_CERT_BASE64" | base64 --decode > certificate.p12
       security create-keychain -p temp-password temp.keychain
       security import certificate.p12 -k temp.keychain -P "$DEVELOPER_ID_CERT_PASSWORD"
   ```

### GitHub Token Setup and Management

#### Creating HOMEBREW_TAP_DISPATCH_TOKEN

1. **Generate Personal Access Token**:
   - Go to GitHub Settings > Developer settings > Personal access tokens > Tokens (classic)
   - Click "Generate new token (classic)"
   - Set expiration to 90 days for security
   - Select scopes:
     - `repo` (Full control of private repositories)
   - Generate and copy the token immediately

2. **Configure in Repository Secrets**:
   - Navigate to repository Settings > Secrets and variables > Actions
   - Click "New repository secret"
   - Name: `HOMEBREW_TAP_DISPATCH_TOKEN`
   - Value: The generated Personal Access Token
   - Click "Add secret"

3. **Test Token Permissions**:
   ```bash
   # Test repository dispatch capability
   curl -X POST \
     -H "Authorization: token $HOMEBREW_TAP_DISPATCH_TOKEN" \
     -H "Accept: application/vnd.github.v3+json" \
     https://api.github.com/repos/beriberikix/homebrew-usbipd-mac/dispatches \
     -d '{"event_type":"test"}'
   ```

#### Token Rotation and Maintenance

1. **Rotation Schedule**:
   - Create calendar reminders for token rotation every 90 days
   - Monitor token expiration dates in GitHub settings
   - Plan rotation during low-activity periods to minimize disruption

2. **Rotation Process**:
   ```bash
   # 1. Generate new token with same permissions
   # 2. Update GitHub secret with new token value
   # 3. Test functionality with a test release
   # 4. Revoke the old token
   # 5. Document the rotation date
   ```

3. **Emergency Token Recovery**:
   - Keep backup tokens with similar permissions (separate GitHub account)
   - Document emergency contact procedures for token issues
   - Maintain offline backup of token rotation procedures

#### Token Security Best Practices

1. **Access Control**:
   - Limit token creation to repository administrators only
   - Use separate tokens for different automation purposes
   - Never store tokens in code or commit them to repositories

2. **Monitoring and Auditing**:
   - Review GitHub audit logs regularly for token usage
   - Monitor repository dispatch events for unexpected activity
   - Set up alerts for failed authentication attempts

3. **Minimal Permissions**:
   - Grant only the `repo` scope required for repository dispatch
   - Avoid broader permissions like `admin:repo_hook` unless specifically needed
   - Regular review of token permissions and usage patterns

## Code Signing Commands

### Manual Signing Commands

```bash
# Sign main executable
codesign --sign "Developer ID Application: [Your Name]" \
         --entitlements usbipd.entitlements \
         --options runtime \
         --timestamp \
         --verbose \
         .build/release/usbipd

# Sign System Extension
codesign --sign "Developer ID Application: [Your Name]" \
         --entitlements Sources/SystemExtension/SystemExtension.entitlements \
         --options runtime \
         --timestamp \
         --verbose \
         .build/release/USBIPDSystemExtension

# Verify signing
codesign --verify --deep --strict --verbose=2 .build/release/usbipd
spctl --assess --type execute --verbose .build/release/usbipd
```

### Automated Signing in CI

Template for GitHub Actions workflow:

```yaml
name: Code Signing

on:
  push:
    tags: ['v*']

jobs:
  sign-and-package:
    runs-on: macos-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Setup signing certificates
        env:
          DEVELOPER_ID_CERT_BASE64: ${{ secrets.DEVELOPER_ID_APPLICATION_CERT_BASE64 }}
          DEVELOPER_ID_CERT_PASSWORD: ${{ secrets.DEVELOPER_ID_APPLICATION_CERT_PASSWORD }}
        run: |
          # Import certificates
          echo "$DEVELOPER_ID_CERT_BASE64" | base64 --decode > certificate.p12
          security create-keychain -p temp-keychain temp.keychain
          security default-keychain -s temp.keychain
          security unlock-keychain -p temp-keychain temp.keychain
          security import certificate.p12 -k temp.keychain -P "$DEVELOPER_ID_CERT_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: -s -k temp-keychain temp.keychain
      
      - name: Build and sign
        env:
          APPLE_TEAM_ID: ${{ secrets.APPLE_DEVELOPER_TEAM_ID }}
        run: |
          swift build --configuration release
          
          # Sign executables
          codesign --sign "Developer ID Application: [Your Name] ($APPLE_TEAM_ID)" \
                   --entitlements usbipd.entitlements \
                   --options runtime \
                   --timestamp \
                   .build/release/usbipd
          
          codesign --sign "Developer ID Application: [Your Name] ($APPLE_TEAM_ID)" \
                   --entitlements Sources/SystemExtension/SystemExtension.entitlements \
                   --options runtime \
                   --timestamp \
                   .build/release/USBIPDSystemExtension
      
      - name: Create signed package
        env:
          INSTALLER_CERT: "Developer ID Installer: [Your Name] (${{ secrets.APPLE_DEVELOPER_TEAM_ID }})"
        run: |
          pkgbuild --root .build/release \
                   --identifier com.yourteam.usbipd-mac \
                   --version ${{ github.ref_name }} \
                   --sign "$INSTALLER_CERT" \
                   usbipd-mac-${{ github.ref_name }}.pkg
      
      - name: Verify signatures
        run: |
          codesign --verify --deep --strict --verbose=2 .build/release/usbipd
          codesign --verify --deep --strict --verbose=2 .build/release/USBIPDSystemExtension
          spctl --assess --type install --verbose usbipd-mac-${{ github.ref_name }}.pkg
```

## Development vs Production Configuration

### Development Configuration

- Use `Apple Development` certificates for local testing
- Enable `com.apple.security.get-task-allow` for debugging
- Disable hardened runtime restrictions during development
- Use local provisioning profiles

### Production Configuration

- Use `Developer ID Application` certificates for distribution
- Disable `com.apple.security.get-task-allow` in production builds
- Enable full hardened runtime protections
- Sign with timestamp and runtime flags

## Troubleshooting

### Common Issues

1. **Certificate Not Found**:
   ```bash
   # List available certificates
   security find-identity -v -p codesigning
   
   # Import certificate if missing
   security import certificate.p12 -k ~/Library/Keychains/login.keychain-db
   ```

2. **Entitlements Validation Errors**:
   - Ensure App IDs match bundle identifiers exactly
   - Verify all required capabilities are enabled in Apple Developer Portal
   - Check entitlements file syntax with `plutil -lint`

3. **System Extension Installation Failures**:
   - Verify System Extension entitlements include all required permissions
   - Check that main app and System Extension are signed with same certificate
   - Ensure proper bundle ID hierarchy (main app as parent)

4. **CI Signing Failures**:
   - Verify all secrets are properly configured
   - Check certificate validity dates
   - Ensure keychain is properly unlocked in CI environment

### Verification Commands

```bash
# Verify certificate chain
security verify-cert -c certificate.crt

# Check entitlements
codesign -d --entitlements :- signed_executable

# Test System Extension loading
systemextensionsctl list
systemextensionsctl reset
```

## Security Best Practices

1. **Certificate Management**:
   - Store certificates securely using GitHub encrypted secrets
   - Use separate certificates for development and production
   - Regularly rotate certificates before expiration

2. **Entitlements**:
   - Use minimal required entitlements for each target
   - Remove development entitlements from production builds
   - Document all entitlements and their purposes

3. **Access Control**:
   - Limit access to signing certificates and secrets
   - Use separate Apple Developer accounts for different environments
   - Enable two-factor authentication on all Apple Developer accounts

4. **Validation**:
   - Always verify signatures after signing
   - Test signed binaries on clean systems
   - Validate System Extension installation in isolated environments

## References

- [Apple Code Signing Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/)
- [System Extensions and DriverKit](https://developer.apple.com/documentation/systemextensions)
- [Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime)
- [Notarization Process](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)