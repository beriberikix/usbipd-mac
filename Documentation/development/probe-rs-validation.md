# End-to-end validation with probe-rs

The transfer path was previously proven only by a control transfer issued from a
purpose-built Python client. That client was written against this server's behaviour,
so it could not catch a misreading shared by both sides, and it never touched a bulk
endpoint. Driving a real embedded-development tool over the wire closes both gaps.

## Setup

A SEGGER J-Link (`1366:0101`) bound on the macOS host, and probe-rs running on Linux
in Docker. Docker Desktop's LinuxKit kernel has `vhci_hcd` built in, so no VM is
needed — `--privileged` is enough, plus `-v /dev/bus/usb:/dev/bus/usb` so probe-rs can
reach the device node.

```
usbipd bind 1-17 && usbipd daemon
docker run --rm --privileged -v /dev/bus/usb:/dev/bus/usb usbip-probers bash -c \
  'usbip attach -r host.docker.internal -b 1-17 && probe-rs info'
```

## Result

| | probe-rs list | VTref reading |
| --- | --- | --- |
| macOS, direct | J-Link, serial `000801032667` | 0.00 V |
| Linux, over USB/IP | J-Link, serial `000801032667` | 0.86 V |

Both stop at the same place: no target chip is attached, so probe-rs cannot identify
one. VTref is a live analog measurement read from the probe over bulk, and the two
readings differ because the input floats with nothing connected. Reading it at all is
the point — it is not a descriptor value, it comes back only if a command written to
the bulk OUT endpoint produced a reply on the bulk IN endpoint.

`Scripts/verify-jlink-bulk.py` does the same exchange without probe-rs, which is what
made the failures diagnosable: it writes `EMU_CMD_VERSION` and reads the reply.

```
bulk OUT (EMU_CMD_VERSION): status=0 written=1
bulk IN  (64-byte read):    status=0 actual=2 data=7000
probe says the version string is 112 bytes
bulk IN  (version string):  status=0 actual=112
-> 'J-Link EDU Mini V1 compiled Sep 17 2025 12:04:20'
```

## Three defects this found

**Read buffers were declared empty.** `ReadPipeTO`'s size argument is in/out: on entry
the buffer capacity, on return the bytes read. It was initialised to 0 and never set,
so IOKit was told the buffer could hold nothing and any packet the device sent overran
it — `kIOReturnOverrun`, reaching the client as EMSGSIZE. **Every IN transfer on the
bulk and interrupt paths failed this way.** The control path was unaffected, which is
why a control-only test suite reported success.

**Transfer type was guessed from the request.** CMD_SUBMIT carries no transfer type, so
the server must learn it from the device. The code guessed, treating a non-zero
interval as interrupt. A J-Link declares `bInterval 1` on both of its *bulk* pipes and
the Linux client passes that through, so its bulk traffic was routed to the interrupt
path. The type now comes from `GetPipeProperties`.

**Pipe references were endpoint numbers.** IOKit addresses pipes by a 1-based index
into the interface, not by endpoint number; the code used `endpoint & 0x7F`. The two
coincide on simple devices and diverge as soon as an interface has gaps or several
endpoints. There was a standing `TODO: Add endpoint discovery to populate interfaceRefs
with proper pipe references`; that discovery now exists and the index is looked up.

## What this does and does not establish

Established: enumeration, string descriptors, control transfers, and bidirectional bulk
transfers all work against a real Linux client and a real application, on one device.

Not established: interrupt and isochronous endpoints. The interrupt path shares the
in/out length fix and the pipe lookup, so it is better than it was, but no interrupt
device has been driven. A target chip was not attached, so probe-rs never progressed
past probe identification — flashing and debugging are unproven.

## Isochronous is incomplete, not merely untested

A webcam was measured on 2026-08-06 to see whether isochronous could be exercised. It
cannot, and not only because the device is claimed — two structural gaps would stop it
even on a device that opened freely:

- **Alternate settings are never selected.** A UVC video interface carries its
  isochronous endpoints only in non-zero alternate settings; at setting 0 it has none,
  which is how USB reserves bandwidth. A client selects one with a `SET_INTERFACE`
  control request, and nothing in this codebase handles that request or calls IOKit's
  `SetAlternateInterface`.
- **Pipes are discovered once, at open.** `discoverPipes` runs when the interface is
  opened and never again, so the pipe map reflects setting 0 permanently. Even if a
  client did switch settings, the endpoints that appeared would not be visible.

Isochronous therefore needs alternate-setting support before it can be tested at all,
rather than a device to test it against. That is a design gap, not a missing fixture.
