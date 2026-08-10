# App bundle and DriverKit extension — the remaining phase

Phase 1 (the enabling cleanup) landed in 0.7.0: the System Extension subsystem was
removed, ~25,800 lines with it, and the release stopped publishing an extension bundle
nothing could install. This document is what is left, and it is **gated entirely on
Apple granting the DriverKit capability**. Nothing here is worth starting before that.

## Why an app bundle at all

Devices whose interfaces macOS holds cannot be served. Measured on this project's
hardware:

| Device class | Result |
|---|---|
| HID (Keychron K3) | `AppleUserHIDDevice` holds it — refused |
| Audio (dock) | `AppleUSBAudioControlNub` — refused |
| FTDI, CP210x | `IOUserSerial` attaches but takes no exclusive access — **served today** |
| **CDC-ACM** | data interface opens; **control interface refuses** |

The CDC-ACM split is the case that matters. Measured on a Raspberry Pi Debug Probe with
`Scripts/validate-usb-entitlements.sh --only 2e8a:000c`:

```
iface 0 (class 255, CMSIS-DAP)   no driver            → kIOReturnSuccess
iface 1 (class 2,   ACM control) AppleUSBACMControl   → kIOReturnExclusiveAccess
iface 2 (class 10,  ACM data)    AppleUSBACMData      → kIOReturnSuccess
```

Control carries `SET_LINE_CODING` and `SET_CONTROL_LINE_STATE` — baud rate, DTR, RTS. A
client can be handed every byte and still never set the line up, so CDC-ACM cannot be
served usefully. That is Arduino, STM32 virtual COM ports, the Pico's UART: the class
most dev boards with native USB present, and the one measured case where a DriverKit
entitlement would change the answer rather than being unnecessary.

Taking that interface needs a dext, and a dext can only be activated by a process inside
an `.app` in `/Applications`. A Homebrew-installed Mach-O is not that.

## Chosen shape: an opt-in activator app

Decided deliberately, because it is the only shape that is **not breaking**.

- The Homebrew **formula stays exactly as it is** — `brew install usbip`,
  `sudo brew services start usbip`, `usbipd …`, `~/.usbipd/`, TCP 3240 all unchanged.
- A new **cask** ships a small `.app` whose only job is hosting and activating the
  extension. Users who do not need driver-bound devices never install it.
- The daemon stays a Homebrew binary and reaches the dext by opening an `IOUserClient`.

Rejected, and why:

| Shape | Why it breaks |
|---|---|
| App hosts the daemon; formula becomes a thin CLI | `sudo brew services start usbip` stops being how the daemon runs |
| Cask replaces the formula | `brew upgrade` does **not** migrate formula → cask. Users silently stall, told they are up to date, until they manually uninstall and reinstall |

## Two things to settle before writing any code

**1. Can a daemon outside the app open an `IOUserClient` on the dext?**
This is load-bearing. The archived entitlements already request
`com.apple.developer.driverkit.allow-any-userclient-access`, and the Apple submission
argues same-team access should not even need it — but it is not proven. If it is false,
the daemon must move into the app and the migration becomes breaking after all. Prove it
before committing.

**2. Which bundle identifier?**
There is a conflict worth resolving deliberately rather than by habit:

- `com.github.usbipd-mac.systemextension` is what has historically been signed.
- `com.usbipd.mac.system-extension` is the App ID that capability request `26F53XCAGY`
  is filed against.

A Developer ID signature needs no registered App ID, but the **provisioning profile** —
which is what makes the managed DriverKit capabilities take effect — does. So the
identifier must match whatever App ID the profile is issued for. Apple additionally
requires the extension's ID to be prefixed by the host app's, which fixes the whole
namespace once chosen:

```
com.usbipd.mac                  ← the activator .app
com.usbipd.mac.system-extension ← the dext inside it
```

## What the app contains

Nothing but activation UI. No USB/IP logic, no daemon, no protocol code.

```
/Applications/<name>.app/
  Contents/
    Info.plist                       CFBundleIdentifier = <app id>
    MacOS/<activator>                minimal app: Activate / Deactivate / Status
    Library/SystemExtensions/
      <app id>.<ext>.dext/
        Info.plist                   IOKitPersonalities, IOUserClass, IOProbeScore
        MacOS/<dext>
        embedded.provisionprofile    non-empty this time
    embedded.provisionprofile
```

**The dext is a rewrite, not a port.** The deleted `Sources/SystemExtension/` was a plain
Swift executable using Foundation, Dispatch and `RunLoop.main`; a dext is C++ against the
DriverKit SDK with none of those. Zero lines carry over, and SwiftPM cannot build either
the app or the dext — Phase 2 adds an Xcode project or `xcodebuild` alongside
`Package.swift`. The archived `Info.plist` and entitlements under
`system-extension-archive/` are useful only as a record of the identifier and entitlement
decisions.

## Signing, notarization, distribution

- **Notarization becomes mandatory.** SIP is enabled on the target machine and
  `systemextensionsctl developer` refuses to run while it is, so there is no
  developer-mode bypass. Tailscale and OBS do exactly this: Developer ID + notarized
  `.app` in `/Applications`.
- The release workflow already has working `notarytool` machinery and all four
  credentials (`DEVELOPER_ID_CERTIFICATE(_PASSWORD)`, `NOTARIZATION_USERNAME/PASSWORD`).
  It needs a `DRIVERKIT_PROVISIONING_PROFILE` secret — referenced by the old workflow but
  never configured, and removed in 0.7.0.
- Sign inside-out: dext first, then the app, `--options runtime --timestamp`. Notarize
  the whole `.app` as one submission and staple it. Stapling works on an `.app`, unlike a
  bare Mach-O — which is why `usbipd` is signed but unnotarized, and can stay that way.
- `com.apple.developer.system-extension.install` goes on **the app**, never on `usbipd`.
  It is restricted: AMFI kills a binary claiming it without an authorising profile,
  measured as exit 137 on launch. That is why 0.7.0 deleted `usbipd.entitlements`.
- Cask in the existing tap, shipping only the `.app` — no `binary` stanza, so it cannot
  collide with the formula's `usbipd`.

## The seam Phase 1 left

`DeviceClaimManager` (`Sources/Common/DeviceClaimProtocol.swift`) survives precisely so
this has somewhere to land. `UserspaceDeviceClaimManager` satisfies it today by tracking
intent; a `DextDeviceClaimManager` would open the user client and issue claim/release
over `IOConnectCallStructMethod`. `RequestProcessor`, `USBRequestHandler` and
`USBDeviceCommunicatorImplementation` already talk to the protocol and need no change.
Selecting between the two is one `if` in `main.swift`, keyed on whether the dext's
service is present.

## Must be re-measured before believing any of this

That a dext with a higher `IOProbeScore` **actually displaces `AppleUSBACMControl`** on a
CDC-ACM device. That is the entire justification, and it has been inferred, not
demonstrated. The previous subsystem's claiming strategy was also plausible on paper and
was measured not to unbind anything.

## Version skew

An independently installed cask and formula can drift apart. Mitigate with a version
handshake over the user client and a clear error, rather than assuming lockstep.
