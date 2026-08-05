# Draft: new Apple Feedback report

Ready to paste into Feedback Assistant. FB22897007 was closed on 2026-08-04 and is
explicitly no longer monitored, so this must be filed as a **new** report.

- **Area:** USB / Thunderbolt
- **Type:** Suggestion (or Incorrect/Unexpected Behavior, if filing about the
  entitlement gate specifically)
- **Attach:** `.build/entitlement-validation/report.md` from a local run of
  `./Scripts/validate-usb-entitlements.sh`

---

## Title

DriverKit USB transport entitlement is the blocker for a USB/IP server on macOS
(follow-up to FB22897007)

## Description

This follows up on FB22897007, which was closed after two weeks. Thank you for the
reply on that report — it was correct, and it revealed that my original report named
the wrong entitlement. I want to correct the record and re-state the request
accurately.

### What the previous report got wrong

FB22897007 said the project "requires the `com.apple.security.device.usb` entitlement
to rebind host USB drivers". Your reply noted that this entitlement needs no request
and can simply be added to the entitlements file. That is accurate.

It is also not the entitlement that gates this work. `com.apple.security.device.usb`
is an App Sandbox entitlement; it relaxes a sandbox restriction. `usbipd` is a
non-sandboxed daemon, so there is nothing for it to relax, and nothing about the App
Sandbox governs whether userspace may take a USB interface from an in-kernel driver.

I have measured this rather than assumed it.

### Measurement

I built a small IOKit probe, compiled once and code-signed five times with different
entitlement sets, then ran each build against the same attached devices. Host: macOS
26.5.2, Apple silicon.

| Variant | Entitlements | J-Link (1366:0101) | Keyboard (2109:d101) |
| --- | --- | --- | --- |
| baseline | none | 1/1 interfaces open | 0/1 — `kIOReturnExclusiveAccess` |
| usb-only | `com.apple.security.device.usb` | 1/1 interfaces open | 0/1 — `kIOReturnExclusiveAccess` |
| sandboxed-only | `app-sandbox` | 0/0 — no IOKit access | 0/0 — no IOKit access |
| sandboxed-usb | `app-sandbox` + `device.usb` | 1/1 interfaces open | 0/1 — `kIOReturnExclusiveAccess` |
| driverkit | `com.apple.developer.driverkit*` | **process killed at launch, exit 137** | — |

Three things follow.

**1. `com.apple.security.device.usb` behaves exactly as documented, and does not help
here.** Compare `sandboxed-only` (0/0) against `sandboxed-usb` (1/1): inside the App
Sandbox the entitlement does restore IOKit USB access. Compare `usb-only` against
`baseline`: outside the sandbox it grants nothing that was not already available. For
a non-sandboxed daemon it is a no-op, which is why adding it changed nothing.

**2. The DriverKit entitlements are a hard gate, not a paperwork step.** Signing with
`com.apple.developer.driverkit`, `com.apple.developer.driverkit.transport.usb` and
`com.apple.developer.driverkit.allow-any-userclient-access` and launching produces
exit 137 — AMFI refusing a restricted entitlement with no matching provisioning
profile. This is a categorically different bar from the App Sandbox entitlement, and
it is the one the project has been waiting on since 2025-08-23.

**3. The blocker is device-class-specific.** The J-Link has no kernel driver bound and
opens cleanly from an unsigned, unentitled, non-root process. The keyboard is owned by
`AppleUserHIDDevice` and returns `kIOReturnExclusiveAccess`. So vendor-specific bulk
devices — debug probes, DFU/bootloader modes — are already serviceable today, while
anything macOS binds a driver to (USB-serial via `AppleUSBFTDI` / `AppleUSBCDCACM`,
HID, mass storage) is not.

### The request

Either of these would unblock this work:

1. **Grant the DriverKit USB transport entitlements** so a driver extension can claim
   an interface from an in-kernel driver, which is the only sanctioned mechanism I am
   aware of for serving driver-bound devices over USB/IP.

2. **Ship a first-party USB/IP server**, the original suggestion in FB22897007. macOS
   remains the only major developer platform without one. Windows ships `usbipd-win`
   as a first-party tool that powers USB device access in both WSL2 and Docker
   Desktop; USB/IP has been in the Linux kernel since 2014. Docker Desktop added
   USB/IP client support in v4.35.0, so the client side already exists on macOS — only
   the server is missing.

If there is a supported path I have overlooked for taking a USB interface from an
in-kernel driver without DriverKit, I would genuinely like to know; that would resolve
this without any entitlement being granted.

### Reproducing

The measurement harness is open source and self-contained:

    git clone https://github.com/beriberikix/usbipd-mac
    cd usbipd-mac
    ./Scripts/validate-usb-entitlements.sh

It compiles one probe, signs it under each entitlement set, runs each against attached
devices, and writes a comparison to `.build/entitlement-validation/report.md`. It is
non-destructive — devices are opened and immediately closed.
