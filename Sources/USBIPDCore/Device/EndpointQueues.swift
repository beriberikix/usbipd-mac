// EndpointQueues.swift
// Decides which transfers may run at the same time.

import Foundation

/// Hands out one serial queue per USB endpoint address.
///
/// This exists as its own type because it encodes a correctness rule that is worth
/// testing on its own, and `IOKitUSBInterface` cannot be constructed without real
/// hardware.
///
/// The rule has two halves, and both matter:
///
/// **Different endpoints must not share a queue.** IOKit's `ReadPipeTO` and
/// `WritePipeTO` block the calling thread until the transfer completes or its timeout
/// expires. With one queue per interface, a pending IN transfer held that queue for its
/// whole timeout and no other transfer could start — including the OUT transfer
/// carrying the command that would have produced the awaited data. Any protocol that
/// reads and writes concurrently deadlocked until the timeout. A Raspberry Pi Debug
/// Probe demonstrated it precisely: probe-rs posted a read on endpoint 0x05, then
/// fifteen writes on 0x04 that sat untouched for sixty seconds, and all fifteen
/// completed within a millisecond of the read finally timing out.
///
/// **The same endpoint must share one.** A USB pipe is a FIFO. Two transfers on one
/// endpoint running concurrently could complete against the device out of order, which
/// no client expects.
///
/// The key is the full endpoint address, direction bit included, because IN 0x85 and
/// OUT 0x05 are distinct pipes that may legitimately be busy at the same time.
final class EndpointQueues: @unchecked Sendable {

    private var queues: [UInt8: DispatchQueue] = [:]

    /// Guards `queues` alone. It is taken only to look up or insert a queue and is
    /// never held while a transfer runs — holding it across a blocking transfer would
    /// reintroduce exactly the serialization this type exists to remove.
    private let lock = NSLock()

    private let label: String
    private let qos: DispatchQoS

    init(label: String = "com.usbipd.iokit-interface", qos: DispatchQoS = .userInitiated) {
        self.label = label
        self.qos = qos
    }

    /// The queue owning transfers on `endpoint`, created on first use.
    ///
    /// Lazy because the endpoints an interface exposes are unknown until it is open and
    /// its pipes discovered, and a client need not use all of them.
    func queue(for endpoint: UInt8) -> DispatchQueue {
        lock.lock()
        defer { lock.unlock() }

        if let existing = queues[endpoint] {
            return existing
        }
        let created = DispatchQueue(label: "\(label).ep\(String(endpoint, radix: 16))", qos: qos)
        queues[endpoint] = created
        return created
    }
}
