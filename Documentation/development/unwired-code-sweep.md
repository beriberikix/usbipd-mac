# Sweep: mechanisms written but never wired

Three bugs in a row shared one shape: a complete, plausible-looking mechanism that
nothing ever invoked. `setUSBRequestHandler`, `setUSBDeviceCommunicator`, and
`ServerConfig.isDeviceAllowed` were each fully written, and each had zero callers.
The tests passed throughout because they exercised the units directly, so the gap
was never between a unit and its assertions — it was between the unit and the daemon.

The last of the three was security-relevant, which prompted this sweep of every
declaration in `Sources/` with no production caller. Run it again with
`Scripts/` absent — the script lives in the session scratchpad; the method is
simply: extract `public`/`internal func` declarations, subtract protocol
requirements, then count call sites outside the declaring file, separately for
`Sources/` and for the two test targets that actually compile.

## Fixed as a result

**Transfer direction was read from the wrong place.** `usbip_header_basic` carries
`ep` (bare endpoint number, 0-15) and `direction` as separate fields; IOKit wants
direction in bit 7 of the endpoint address. The communicator passed `ep` through
untouched and `IOKitUSBInterface` recovered direction with `(endpoint & 0x80)`, so a
conforming client sending `ep=1, direction=IN` had its transfer run as an OUT.
Observed live as `No data provided for bulk OUT transfer`, answered with EINVAL.
Every bulk, interrupt, and isochronous IN transfer from a real client would have
failed. Fixed, with four tests over the mapping.

**`setUSBDeviceCommunicator` removed.** After its work moved into
`USBRequestHandler.init`, it was dead. Leaving it would have preserved the exact trap
that caused the original bug: a setter that looks like the wiring point and is not.

## Removed: mechanisms with tests but no production callers

Deleting these removed 42 tests. That is the point — they were green tests over code
the daemon never reached, and their passing actively disguised that nothing used it.

| Removed | Why it was safe |
| --- | --- |
| `URBTracker` and its ~30 tests | a dead duplicate; UNLINK cancels through `USBSubmitProcessor.cancelURB`, which tracks URBs in `activeURBs` |
| `DeviceMonitor` (192 lines) and its tests | hotplug is handled directly by `deviceDiscovery.onDeviceConnected`/`onDeviceDisconnected` in `ServerCoordinator` |
| `logDebug`/`logInfo`/`logWarning`/`logError`/`logCritical` globals | an unused parallel API; production uses the `logger.debug(…)` methods in 739 places. Their one test asserted nothing beyond "does not crash" |
| `USBErrorMapping.mapUSBStatusToIOKit` | the reverse direction. The server maps IOKit → USB/IP via `mapIOKitError`, which is live |
| `USBErrorMapping.errorDescription(for:)` (static) | no callers. The *instance* `errorDescription` is `LocalizedError` conformance and was kept |
| `ServerConfig.resetToDefaults` | no callers |
| `CompletionFormattingUtilities.formatDescription` | no callers |
| `CompletionFormattingUtilities.generateFallbackCompletion` | no callers, and stale: it advertised `attach` and `detach`, removed from the CLI |

One near-miss worth recording: the sweep flagged `errorDescription`, but the instance
property of that name is a `LocalizedError` requirement reached through
`localizedDescription`. A sweep keyed on call sites cannot see protocol dispatch, so
every hit needs checking against the conformance list before deletion. Only the static
overload was genuinely unused.

## Now enforced

Every row below was a setting that persisted, loaded, and validated its own range
while nothing read it. Defaults match the constants that were previously hardcoded, so
behaviour is unchanged for anyone who never set them.

| Setting | Where it now applies |
| --- | --- |
| `maxUSBBufferSize` | `USBSubmitProcessor.validateSubmitRequest` bounds the requested transfer |
| `usbOperationTimeout` | replaces the hardcoded 5000 ms URB timeout |
| `maxTotalConcurrentRequests` | replaces the hardcoded 64 in the concurrency check |
| `maxPendingURBsPerDevice` | new per-device cap, so one busy device cannot consume the global budget |
| `maxConnections` | `TCPServer` refuses connections past the limit; the accept path was unbounded |
| `connectionTimeout` | `TCPServer` reaps idle connections |

Two consequences worth stating.

**Reaping needed an exemption.** An attached USB/IP session is legitimately silent for
long stretches — an idle keyboard sends nothing — so a plain idle timeout would have
killed exactly the sessions that work. Connections are marked `keepAlive` once they
carry an attached device, and the reaper skips them. Enforcing `maxConnections` is also
what made `connectionTimeout` matter: with a cap of 10 and no reaping, ten silent
clients lock everyone out.

**Rejections are now answered.** Validation failures used to throw, and a thrown error
reaches `ServerCoordinator`, which logs it and sends nothing — the client waits on a
reply that never arrives. Rejected requests now return a `RET_SUBMIT` carrying the
error. Measured: a 64 MiB request against a running daemon returns
`status=-22` immediately, where it previously blocked in `ReadPipe` until the client
timed out.

`autoBindDevices` was removed rather than implemented. Auto-binding every newly
connected device is the opposite of the opt-in model the allow-list establishes, so
wiring it would have undone that deliberately. Removing an unused key is safe for
existing config files: Swift's synthesized `Codable` ignores keys it does not know.

`validateUSBIPMessage` and `validateSetupPacket` were deleted rather than wired. Their
checks now live in `validateSubmitRequest`, which is actually called, and one of the
originals was broken anyway: `endpoint & 0x0F > 15` can never be true, since a nibble
is at most 15.

## Reading the residue

Most remaining zero-caller hits are inside the quarantined System Extension subsystem
and are expected — that code is inert by design. The signal is confined to
`USBIPDCore` outside `SystemExtension/`, `USBIPDCLI`, and `Common`.

The `TESTS-ONLY` category deserved the same suspicion as `DEAD`, and is now empty for
live code. A mechanism with tests but no production callers is not covered — it is a
well-tested spare part whose green tests obscure that nothing uses it.

Re-running the sweep is the cheap way to keep it that way. What remains is confined to
the quarantined System Extension subsystem, which is inert by design, and to the
`config.*` and validator rows above, which are unwired behaviour rather than unused
code and need decisions rather than deletions.
