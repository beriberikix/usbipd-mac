# DriverKit Serial entitlement request

> **Superseded by measurement. Do not build on this.**
>
> The request rests on the claim that USB-serial adapters cannot be served because
> macOS holds their interfaces, and that "there is no userspace path". That is wrong.
> `IOUserSerial` attaches to FTDI and CP210x interfaces without taking exclusive
> access, so they open and serve normally; v0.6.0 ships this, verified against an FTDI
> Quad RS232-HS and a CP2102N.
>
> So the request asks Apple for the one DriverKit family the project has since proven
> it does not need. What remains genuinely blocked — HID, mass storage, audio, cameras
> — belongs to different families and is not covered by this request.
>
> The submission cannot be edited or withdrawn from the developer portal. It is left to
> run its course; granted or denied, nothing depends on it. Read the rest of this file
> as a record of what was submitted, not as a statement of what is true.

**Submitted 2026-08-06. Request ID `26F53XCAGY`.** Serial family only, development tier.
Status appears under Capability Requests for App ID `com.usbipd.mac.system-extension`.

The Capability Requests tab shows this request as **Submitted**, and confirms the
closing sentence: `DriverKit PCI (development)` really is `Assigned`, so the submitted
text is accurate as written. Note that the account holder does not recall requesting
that capability, so it is likely assigned to Developer Program accounts rather than
granted on merit — true as stated, but not evidence of precedent.

The text submitted is below, kept so a follow-up or re-request can build on it rather
than start over.

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
