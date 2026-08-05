# Scope: a driver-free CLI release

## Why this is possible

Measured on 2026-08-05 with `./Scripts/validate-usb-entitlements.sh`, macOS 26.5.2,
Apple silicon:

| Device | Kernel driver | Interfaces opened | Verdict |
| --- | --- | --- | --- |
| SEGGER J-Link `1366:0101` | none | 1/1, `kIOReturnSuccess` | usable today |
| USB Keyboard `2109:d101` | `AppleUserHIDDevice` | 0/1, `kIOReturnExclusiveAccess` | blocked |

The J-Link opened from an **unsigned, unentitled, non-root** process. No System
Extension, no DriverKit, no Apple approval. The project's own `IOKitUSBInterface` was
then driven against the same device and completed `open()` and `close()`.

So the blocker is per-device-class, not project-wide. The README's "will not work
until approved" is wrong for a meaningful slice of embedded hardware.

## What ships and what does not

| Works today | Still blocked |
| --- | --- |
| Debug probes — J-Link, ST-Link, CMSIS-DAP | USB-serial — FTDI, CP210x, CH340 |
| DFU / bootloader modes | Boards exposing CDC ACM (most Arduino-likes) |
| Vendor-specific bulk interfaces generally | HID, mass storage, audio |

Only the J-Link and a HID keyboard have actually been measured. The split above is
inferred from the mechanism — whether macOS binds a driver to the interface — and
holds for anything in the left column by that reasoning, but an FTDI adapter and a CDC
board should be measured before the README states it as fact.

**One untested escape hatch:** `USBInterfaceOpenSeize` might displace a kernel driver.
If it works on a CDC device, the entire right-hand column moves. `--seize` exists in
the harness for exactly this and has never been run against serial hardware. Worth ten
minutes before accepting the split as final.

## Work required

### 1. Detect and refuse driver-bound devices with a clear error

Today `bind` allow-lists anything and only discovers the problem when a transfer fails.
The daemon should determine ownership up front, using the logic already proven in
`Scripts/entitlement-validation/USBClaimProbe.swift`: walk the IORegistry children of
the device node and treat any non-structural class as a claiming driver.

Structural classes to ignore (already established by the probe):
`IOUSBHostDevice`, `IOUSBHostInterface`, `AppleUSBHostCompositeDevice`,
`AppleUSBHostDeviceUserClient`, and the legacy shims.

That last one matters: `AppleUSBHostDeviceUserClient` is a *userspace* client, not a
kernel driver. Counting it as one made a fully usable device report as kernel-owned
during harness development. A different message is warranted — "another process has
this device open" is actionable in a way "a kernel driver owns it" is not.

`bind` should then either refuse with a specific message naming the owning driver, or
allow-list with an explicit warning. Refusing is preferable: silently allow-listing a
device that cannot be served is what the previous behaviour did.

### 2. README

Replace the blanket warning with the split. State plainly which classes work now, that
the DriverKit entitlement gates the rest, and point at
`./Scripts/validate-usb-entitlements.sh` so users can check their own hardware rather
than guess.

### 3. Formula

Nothing to drop yet, and nothing to add. The formula already installs the CLI to
`bin`. The System Extension bundle it stages under
`prefix/Library/SystemExtensions` is inert — `OSSystemExtensionRequest` resolves
extensions inside the *calling app's* bundle and requires that bundle to live in
`/Applications`, so a Homebrew prefix is never consulted. See
`Sources/USBIPDCore/SystemExtension/README.md`.

Removing the sysext resource and the `post_install` instruction to run
`sudo usbipd install-system-extension` would make the formula honest, since that
command cannot succeed as installed. That is a change in the tap repository, not here.

A cask is **not** needed for this release. It becomes the right vehicle only if a real
DriverKit extension appears, since a dext must live in an app bundle in `/Applications`.

### 4. Not required

No System Extension, no DriverKit entitlement, no provisioning profile, no
notarization beyond what already exists. The 20,445-line System Extension subsystem
stays quarantined.

## Honest limits

- **Interop is unproven.** The wire format was corrected and verified against
  `linux/drivers/usb/usbip/usbip_common.h`, and 418 tests pass — but the tests encode
  this project's reading of the spec, so they cannot catch a misreading. No Linux
  client has ever attached to this server. The QEMU harness starts a local test server
  and inspects its log; it boots no VM and runs no `usbip` client.
- **One device measured per category.** J-Link and a keyboard.
- **The transfer path has never moved real data.** `IOKitUSBInterface` opens and closes
  a J-Link; no bulk transfer has been exercised against hardware.

Interop validation is the prerequisite for calling this shippable. Everything else here
is ready.
