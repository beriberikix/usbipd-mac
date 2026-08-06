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

## Confirmed unwired, not yet addressed

| Thing | State | Consequence |
| --- | --- | --- |
| `USBIPMessageValidator.validateUSBIPMessage` | zero callers, production *and* test | the buffer-size bound it contains is never applied |
| `USBIPMessageValidator.validateSetupPacket` | zero callers | setup packets reach IOKit unvalidated |
| `config.maxConnections` | only copied config→config by the `config` command | connection count is unbounded |
| `config.connectionTimeout` | same | idle connections are never reaped |
| `config.autoBindDevices` | same | setting it does nothing |
| `config.maxTotalConcurrentRequests` | zero readers | no global request cap |
| `config.usbOperationTimeout` | zero readers | the URB timeout is hardcoded to 5000 ms in `USBSubmitProcessor` |
| `config.maxUSBBufferSize` | zero readers | see below |
| `config.maxPendingURBsPerDevice` | zero readers | no per-device URB cap |

`config.*` entries are the worst of these for users: the settings are documented,
persisted, and load cleanly, so there is nothing to suggest they are inert.

## Buffer bounds: what was and was not established

`IOKitUSBInterface` guards bulk and isochronous with `bufferLength > 0` only, then
calls `allocate(capacity: Int(bufferLength))` on a `UInt32` taken from the wire —
up to 4 GiB. Interrupt is bounded at 8192. `config.maxUSBBufferSize` exists and is
never read; the validator that would enforce it has no callers.

Measured against a running daemon with a 64 MiB `transfer_buffer_length`: RSS did
not move. That is not evidence of a bound — `allocate` reserves address space and
only faults pages in on touch, so RSS was the wrong instrument. **The size of the
allocation is unbounded by anything in this code; whether it is exploitable was not
established.** A test that settles it needs to watch VSZ, or request a size large
enough to fail outright.

Separately, that request never returned: with the direction bit set, the daemon
blocked in `ReadPipe` and the client timed out. `USBSubmitProcessor` sets a 5000 ms
URB timeout, and the bulk path uses `ReadPipe` rather than `ReadPipeTO`, so the
timeout is not applied. One client can hang a request indefinitely. Not investigated
further.

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
