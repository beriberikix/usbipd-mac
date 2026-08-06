# Scope: a driver-free CLI release

## Why this is possible

Measured on 2026-08-05 with `./Scripts/validate-usb-entitlements.sh`, macOS 26.5.2,
Apple silicon:

| Device | Kernel driver | Interfaces opened | Verdict |
| --- | --- | --- | --- |
| SEGGER J-Link `1366:0101` | none | 1/1, `kIOReturnSuccess` | usable today |
| USB Keyboard `2109:d101` | `AppleUserHIDDevice` | 0/1, `kIOReturnExclusiveAccess` | blocked |
| Toshiba flash drive `0930:1400` | `IOUSBMassStorageDriver` | 0/1, `kIOReturnExclusiveAccess` | blocked |

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

Three devices have been measured: an unbound debug probe, a HID keyboard, and a mass
storage drive. The first is usable and the other two are blocked, which is what the
mechanism predicts. USB-serial specifically is still inferred rather than measured —
no FTDI or CDC device has been available — but it is bound by the same
`AppleUSBACMData`-style driver attachment, so there is no reason to expect a different
outcome.

**The escape hatch does not exist.** `USBInterfaceOpenSeize` was the hope that the
right-hand column might move. Measured against a mass storage device on 2026-08-06, it
returns `kIOReturnExclusiveAccess` — the identical error a plain `USBInterfaceOpen`
returns. Seizing does not displace a kernel driver.

Two weaker forms of the same idea also fail:

| Attempt | Result |
| --- | --- |
| `USBInterfaceOpen` | `kIOReturnExclusiveAccess` |
| `USBInterfaceOpenSeize` | `kIOReturnExclusiveAccess` — no different |
| `diskutil unmountDisk` then open | still `kIOReturnExclusiveAccess`; the filesystem detaches but `IOUSBMassStorageDriver` stays bound |
| `diskutil eject` then open | still `kIOReturnExclusiveAccess`; the media stack drops from 20 IOKit nodes to 7, and the interface remains owned |

Worth noting the device/interface split: after unmounting, `USBDeviceOpen` **succeeds**
(`kIOReturnSuccess`) while `USBInterfaceOpen` on the same device still fails. Opening
the device is not the operation that matters — claiming its interface is, and that is
what the kernel driver holds.

So the split is final for the hardware available: nothing short of DriverKit rebinding
releases an interface macOS has bound. Scope the release accordingly rather than
waiting on a workaround.

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

- **Interop is proven for the handshake, not the full session.** The wire format was
  verified against `linux/drivers/usb/usbip/usbip_common.h`, and a real Linux `usbip`
  client (Docker LinuxKit, which has `vhci_hcd` built in) completes both `list` and
  `attach` against this server. Note the QEMU harness is not what established this — it
  starts a local test server and inspects its log; it boots no VM and runs no client.
- **One device measured per category.** J-Link and a keyboard.
- **Only control transfers have moved real data.** A GET_DESCRIPTOR control transfer
  against the J-Link returns its genuine 18-byte device descriptor over USB/IP
  (`Scripts/verify-usb-transfer.py`). Bulk, interrupt, and isochronous transfers remain
  unexercised against hardware.

Interop validation is the prerequisite for calling this shippable. Everything else here
is ready.
