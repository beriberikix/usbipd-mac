# DriverKit Serial entitlement request — draft

Paste the body below into "Describe your apps and how they'll use these entitlements."

**Form settings:** entitlement type `DriverKit Entitlement`; check **Serial** only.
Do not re-check UserClient Access — it was declined on 25 February 2026, and it is not
needed: it exists so *third-party* apps can open a user client on your dext, whereas
the dext and the daemon here are signed by the same team.

**Company / Product URL:** `https://github.com/beriberikix/usbipd-mac`

---

Team ID: 592A3U6J26 (Golioth, Inc.)
Product: usbipd-mac — https://github.com/beriberikix/usbipd-mac

usbipd-mac is an open-source implementation of the USB/IP protocol for macOS. It lets a
Mac share a locally attached USB device over the network so that a Linux machine, VM, or
container can use it as though it were plugged in directly. It is the macOS counterpart
to the usbip tools that ship with the Linux kernel, and it speaks the same wire protocol,
so standard Linux clients work against it unmodified.

The audience is embedded and firmware development. Engineers work on a Mac while the
toolchain, test runners, and CI images are Linux. Today that means physically moving
cables, or keeping a second machine on the desk purely to hold a debug probe or a serial
adapter.

We have shipped a working release, and it is deliberately limited. Devices macOS has not
bound a driver to are served end to end today: enumeration, control transfers, and
bidirectional bulk transfers, verified against real hardware with probe-rs driving a
SEGGER J-Link and with an Android device answering ADB protocol messages over the wire.
No entitlement is involved in that path.

USB-serial adapters — FTDI, CP210x, CH340 — are the most requested devices we cannot
support, because macOS binds a driver to the interface and a userspace process cannot
claim it. We measured this rather than assuming it: a plain USBInterfaceOpen and
USBInterfaceOpenSeize both return kIOReturnExclusiveAccess, and neither unmounting nor
ejecting releases the device. The measurement harness and its results are published in
the repository.

We are requesting the Serial family so we can build a DriverKit extension that binds
these adapters and hands their traffic to the usbipd daemon, which then serves them over
USB/IP exactly as it already serves unbound devices. The extension would match on
USB-serial interfaces only. The daemon is signed by the same team, so no third-party
user client access is required.

We would appreciate the development tier to prove the approach before requesting
distribution. Our account already holds an assigned DriverKit PCI (development)
capability, so the provisioning path is established.
