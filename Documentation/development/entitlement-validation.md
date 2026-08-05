# USB Entitlement Validation

How to empirically determine what actually blocks usbipd-mac on macOS, and how to
turn that into evidence Apple can act on.

## Background: FB22897007

FB22897007 ("Ship a first-party USB/IP server for macOS") described the blocker as:

> it requires the `com.apple.security.device.usb` entitlement to rebind host USB
> drivers. That entitlement request has been pending since August 2025 with no response.

Apple replied:

> `com.apple.security.device.usb` entitlement does not require entitlement request to
> use. You should be able to add it to your app's entitlements file directly without
> going through a formal approval process.

**Apple's answer is correct, and it answers a different question than the one we meant
to ask.** The report named the wrong entitlement. Apple responded accurately about that
entitlement, we did not correct the record within two weeks, and the report was closed
on 4 Aug 2026 and is no longer monitored.

### Why the named entitlement is the wrong one

`com.apple.security.device.usb` is an **App Sandbox** entitlement. It appears in Apple's
documentation under *App Sandbox → Hardware*, and its only function is to punch a hole
in the sandbox for a process that has `com.apple.security.app-sandbox` enabled. Two
consequences follow:

1. `usbipd` is a **non-sandboxed daemon**. An entitlement that relaxes a sandbox has
   nothing to relax in a process that is not sandboxed. Adding it to
   `usbipd.entitlements` — which the project already does — is expected to be a no-op.
2. Nothing about the App Sandbox governs IOKit driver matching. Whether a USB device
   is already bound to an in-kernel driver, and whether userspace may take it away,
   is decided entirely outside the sandbox.

### What actually gates the capability

Detaching a USB device from its in-kernel driver requires a **DriverKit** driver
matching the device at a higher probe score, which requires this family of managed
entitlements:

| Entitlement | Approval |
| --- | --- |
| `com.apple.developer.driverkit` | Apple review required |
| `com.apple.developer.driverkit.transport.usb` | Apple review required |
| `com.apple.developer.driverkit.allow-any-userclient-access` | Apple review required |

These are *managed capabilities*: they are only honoured when the same keys appear in
an Apple-issued provisioning profile embedded in the signed binary. Ad-hoc signing them
does not work — AMFI kills the process at launch. That launch failure is itself
reproducible evidence, and the validation harness captures it.

This is the request that has been pending since August 2025. It is a materially higher
bar than the App Sandbox entitlement Apple pointed at, and it is the thing worth
re-filing about.

## Two findings in the shipped entitlement files

The validation script audits the project's own entitlement files and flags two problems
that exist independently of any Apple decision:

1. **`Sources/SystemExtension/SystemExtension.entitlements` misspells the USB transport
   key.** It requests `com.apple.developer.driverkit.usb.transport`. The real key is
   `com.apple.developer.driverkit.transport.usb`. A key that is not a real entitlement
   is silently ignored — it does not error, it simply never grants anything, and it
   would not match a provisioning profile.

2. **The same file requests `com.apple.developer.endpoint-security.client`.** That is a
   separately-reviewed managed capability for security-monitoring products, unrelated to
   USB. Bundling it into a DriverKit request broadens the ask considerably and is a
   plausible contributor to a request sitting unanswered.

Neither is a substitute for the missing approval, but both should be fixed before
re-filing, so the request describes exactly what the project needs and nothing more.

## The experiment

`Scripts/validate-usb-entitlements.sh` compiles one standalone probe
(`Scripts/entitlement-validation/USBClaimProbe.swift`), signs it five times with
different entitlement sets, and runs each build against the USB devices currently
attached. Comparing the runs isolates the effect of each entitlement.

| Variant | Entitlements | What it measures |
| --- | --- | --- |
| `baseline` | none | What usbipd-mac can do today |
| `usb-only` | `device.usb` | Apple's suggestion, taken literally |
| `sandboxed-only` | `app-sandbox` | Negative control for the pair below |
| `sandboxed-usb` | `app-sandbox` + `device.usb` | The only context where `device.usb` is defined to do anything |
| `driverkit` | DriverKit family | Expected to be denied at launch — the real gate |

For each attached device the probe records:

- which kernel driver classes are currently attached below the device in the IORegistry;
- the result of `IOCreatePlugInInterfaceForService` and `USBDeviceOpen`;
- per interface, the attached driver and the result of `USBInterfaceOpen`;
- optionally (`--seize`) the result of `USBDeviceOpenSeize` / `USBInterfaceOpenSeize`.

The interface-level result is the one that matters. A USB/IP server has to own the
interfaces to forward transfers, and interfaces are the level at which in-kernel drivers
bind.

## Running it

```bash
# Attach the device you actually want to share first — a serial adapter, a debug
# probe, a board in DFU mode. Then:
./Scripts/validate-usb-entitlements.sh

# Non-destructive survey only: who owns what, no opens attempted
./Scripts/validate-usb-entitlements.sh --list-only

# Root changes some IOKit outcomes — capture both
sudo ./Scripts/validate-usb-entitlements.sh

# Try to take a device away from its current driver. This can disconnect it.
./Scripts/validate-usb-entitlements.sh --seize
```

Outputs land in `.build/entitlement-validation/`:

- `<variant>.json` — machine-readable results per variant
- `<variant>.log` — console output per variant
- `<variant>.effective-entitlements.xml` — what the signature actually carries, read
  back from the binary rather than assumed
- `report.md` — cross-variant comparison, ready to attach to a Feedback report

## Reading the results

**If `baseline`, `usb-only`, and `sandboxed-usb` are identical** — the expected outcome —
that is a direct, reproducible demonstration that `com.apple.security.device.usb` does
not grant usbipd-mac anything, and the report's premise (that this key was the blocker)
was wrong in a way that does not help.

**Per-device, the `Kernel driver` column splits the fleet in two:**

- *No driver listed* — the device is already fully usable from userspace, today, with no
  entitlement of any kind. Typically vendor-specific-class devices: many debug probes,
  DFU/bootloader modes, and boards that expose a raw vendor interface.
- *A driver listed* (`AppleUSBACM`, `IOUSBHostHIDDevice`, `IOUSBMassStorageDriverNub`,
  `AppleUSBFTDI`, `AppleUSBAudio`, …) — the device is claimed by the kernel and cannot be
  served without DriverKit-level rebinding.

That split is worth knowing on its own. The README currently states the project "will not
work until approved"; if a meaningful share of embedded hardware falls into the first
category, a device-class-scoped release is possible without waiting on Apple at all.

**If `--seize` succeeds where a plain open failed**, that is a third path worth
investigating: `USBInterfaceOpenSeize` can displace some clients without DriverKit.

## A caveat about the current claim implementation

Independently of entitlements, `Sources/SystemExtension/IOKit/DeviceClaimer.swift`
attempts to claim devices by setting `IOMatchCategory` and `IOProbeScore` registry
properties from userspace and calling `IOServiceRequestProbe`. Setting registry
properties on a live `IOService` from userspace routes to the driver's `setProperties()`,
which the USB host drivers do not implement for these keys — so this path does not
unbind anything, and would not do so even with the DriverKit entitlements granted.

The probe deliberately measures the real capability (can the interface be opened) rather
than exercising that code path, so the results are not confounded by it. Fixing the claim
strategy is separate work, and only worth doing once the measurements say which of the
three paths above is viable.

## Next steps after a run

1. Run the harness with the target hardware attached, as both user and root.
2. If the results confirm the expected outcome, **file a new Feedback report** —
   FB22897007 is closed and explicitly no longer monitored. The new report should:
   - reference FB22897007 and thank Apple for the clarification;
   - state plainly that the original report named the wrong entitlement;
   - name `com.apple.developer.driverkit.transport.usb` and the associated DriverKit
     entitlements as the actual request, pending since August 2025;
   - attach `report.md` as the evidence that the App Sandbox entitlement changes nothing;
   - restate the original ask (a first-party USB/IP server) as the alternative that would
     make the entitlement request moot.
3. Fix the two entitlement-file findings above before re-filing.
4. Update the README warning to name the correct entitlement and, if the results support
   it, to scope the warning to device classes that are actually blocked.
