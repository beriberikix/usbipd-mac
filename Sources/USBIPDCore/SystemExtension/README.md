# System Extension subsystem — read this before working here

**Status: quarantined.** This subsystem does not currently work, cannot be made to
work by fixing bugs inside it, and is not on the critical path. Do not treat the
stubs and TODOs in this directory as a backlog to complete.

It is 20,445 lines across `Sources/USBIPDCore/SystemExtension/` and
`Sources/SystemExtension/` — roughly 2.6× the size of the USB/IP implementation it
exists to support (Protocol + Device + Network total 7,945 lines).

## Three independent reasons it does not work

### 1. It cannot be activated from a Homebrew install

`SystemExtensionInstaller.swift` submits the extension with:

```swift
OSSystemExtensionRequest.activationRequest(
    forExtensionWithIdentifier: bundle.bundleIdentifier,
    queue: .main
)
```

That API takes an **identifier, not a path**. macOS resolves it by looking inside
`Contents/Library/SystemExtensions/` of *the calling process's own main bundle*, and
additionally requires that bundle to live in `/Applications`.

`usbipd` is a bare Mach-O at `/opt/homebrew/bin/usbipd`. It is not an app bundle, so
there is nothing to search — the result is `.extensionNotFound`. Even wrapped in a
bundle in place, a Homebrew Cellar path yields `.unsupportedParentBundleLocation`.
Both cases are already handled in `SystemExtensionInstaller.swift`, which suggests
they have been observed.

`SystemExtensionBundleDetector.swift` carefully searches
`/opt/homebrew/Cellar/usbip/<version>/Library/SystemExtensions/` and finds the bundle.
That search is looking somewhere the OS will never consult; the path it returns is
discarded at the call above.

**There is no path-based activation API.** No amount of code in this directory fixes
this. It is a distribution-shape problem: a cask installing an `.app` to
`/Applications`, or dropping the extension entirely.

### 2. The device claim strategy does not claim anything

`Sources/SystemExtension/IOKit/DeviceClaimer.swift` attempts to take a device from its
kernel driver by setting `IOMatchCategory` and `IOProbeScore` registry properties from
userspace and calling `IOServiceRequestProbe`. Setting registry properties on a live
`IOService` routes to that driver's `setProperties()`, which the USB host drivers do
not implement for these keys. Nothing is unbound. This would remain true even with the
DriverKit entitlements granted.

### 3. The DriverKit entitlement is not granted

Rebinding a device away from its in-kernel driver requires
`com.apple.developer.driverkit`, `com.apple.developer.driverkit.transport.usb`, and
`com.apple.developer.driverkit.allow-any-userclient-access` — managed capabilities
requiring both Apple approval and a provisioning profile embedded in the bundle. The
request has been pending since 2025-08-23.

See `Documentation/development/entitlement-validation.md`. Note that Apple's reply to
FB22897007 pointed at `com.apple.security.device.usb`, which is an App Sandbox
entitlement and does nothing here.

## What decides this subsystem's future

Run `./Scripts/validate-usb-entitlements.sh` on a Mac with the target hardware
attached. It reports, per attached device, whether a kernel driver owns it.

- **Devices with no driver bound** are already fully usable from userspace with no
  entitlement and no system extension. A plain root daemon serves them today.
- **Devices with a driver bound** need DriverKit rebinding, which needs all three
  problems above solved.

If the measurement shows that enough target hardware falls into the first category,
this entire subsystem becomes optional and the project can ship without it.

Until that measurement exists, this code stays as-is: building, not invested in, and
not blocking anything.

## If you are here to fix a bug

Check first whether the bug matters. A defect in bundle creation, code signing
verification, or installation diagnostics is a defect in a code path that cannot reach
a working outcome. The stubs concentrated in `Installation/` — particularly
`InstallationVerificationManager.swift` — are placeholders for a workflow that has
never completed successfully end to end.
