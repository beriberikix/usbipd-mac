# DriverKit Serial entitlement request — draft

Paste the body below into "Describe your apps and how they'll use these entitlements."

**Form settings:** entitlement type `DriverKit Entitlement`; check **Serial** only.
Do not re-check UserClient Access — it was declined on 25 February 2026, and it is not
needed: it exists so *third-party* apps can open a user client on your dext, whereas
the dext and the daemon here are signed by the same team.

**Company / Product URL:** `https://github.com/beriberikix/usbipd-mac`

---

The field truncates at roughly 2000 characters — an earlier 2197-character draft was cut
mid-sentence. This is 1707.

Team ID: 592A3U6J26. Product: usbipd-mac, https://github.com/beriberikix/usbipd-mac

usbipd-mac is an open-source USB/IP server for macOS. It shares a locally attached USB device over the network so a Linux machine, VM, or container can use it as if plugged in directly. It speaks the same wire protocol as the Linux kernel's usbip tools, so standard Linux clients work against it unmodified. The audience is embedded development: engineers work on a Mac while their toolchain and CI are Linux.

We have shipped a working release. Devices macOS has not bound a driver to are served end to end today - enumeration, control transfers and bidirectional bulk transfers - verified against real hardware with probe-rs driving a SEGGER J-Link. No entitlement is involved in that path.

USB-serial adapters (FTDI, CP210x, CH340) are the most requested devices we cannot support, because macOS binds a driver to the interface. We measured this rather than assuming it: USBInterfaceOpen and USBInterfaceOpenSeize both return kIOReturnExclusiveAccess, and neither unmounting nor ejecting releases the device. There is no userspace path. The harness and results are published in the repository.

We are requesting the Serial family to build a DriverKit extension that binds these adapters and hands their traffic to the usbipd daemon, which serves them over USB/IP exactly as it already serves unbound devices. The extension would match USB-serial interfaces only. The daemon is signed by the same team, so no third-party user client access is needed.

We would like the development tier to prove the approach before requesting distribution. Our account already holds an assigned DriverKit PCI (development) capability.
