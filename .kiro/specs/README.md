# Historical planning records — not current documentation

These are specifications written before or during implementation. They are kept as a
record of what was intended at the time, and they are **not** maintained against the
code. Several describe subsystems that were later quarantined or removed:

- The System Extension specs describe a subsystem no shipping path activates.
  `OSSystemExtensionRequest` resolves extensions inside the calling app's bundle and
  requires that bundle to live in `/Applications`, so a Homebrew install never
  consults it.
- The QEMU testing specs describe a VM-based harness. What exists starts a local test
  server and inspects its log; it boots no VM and runs no `usbip` client. Interop is
  validated with a Linux client in Docker instead.
- Specs describing `attach` and `detach` predate their removal — attaching is a
  client-side operation macOS cannot perform.

For what the project actually does today, read:

- [`README.md`](../../README.md) — which devices can be shared, and which cannot
- [`Documentation/development/driver-free-release.md`](../../Documentation/development/driver-free-release.md) — measured device support
- [`Documentation/development/probe-rs-validation.md`](../../Documentation/development/probe-rs-validation.md) — end-to-end validation and its limits
- [`Documentation/development/testing-strategy.md`](../../Documentation/development/testing-strategy.md) — what the test suite actually is
