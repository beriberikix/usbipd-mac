// EndpointQueuesTests.swift
// A transfer that blocks one endpoint must not block the others.

import XCTest
@testable import USBIPDCore

final class EndpointQueuesTests: XCTestCase {

    // The bug these cover: every transfer on an interface shared one serial queue, and
    // the IOKit transfer calls block their thread until completion or timeout. A read
    // waiting on a bulk IN endpoint therefore stopped the write that would have caused
    // the device to answer it, so the read could only ever end in a timeout.

    // MARK: - Different endpoints proceed independently

    /// The deadlock, reproduced in miniature: hold one endpoint and require another to
    /// finish anyway. Against a single shared queue the second transfer cannot start
    /// until the first releases, and this times out.
    func testBlockedEndpointDoesNotBlockAnother() {
        let queues = EndpointQueues()
        let released = DispatchSemaphore(value: 0)
        let other = expectation(description: "the other endpoint completes")

        // Endpoint 0x05 IN, stuck exactly as ReadPipeTO would be.
        queues.queue(for: 0x05).async {
            released.wait()
        }

        // Endpoint 0x04 OUT — in the real protocol this write is what unblocks the read.
        queues.queue(for: 0x04).async {
            other.fulfill()
        }

        wait(for: [other], timeout: 2.0)
        released.signal()
    }

    /// Direction is part of the endpoint address, and IN 0x85 is a different pipe from
    /// OUT 0x05. Keying on the endpoint number alone would make them share a queue and
    /// restore the deadlock for any device that pairs them — which is most of them.
    func testDirectionsOfOneEndpointNumberAreIndependent() {
        let queues = EndpointQueues()
        let released = DispatchSemaphore(value: 0)
        let out = expectation(description: "the OUT endpoint completes")

        queues.queue(for: 0x85).async { released.wait() }
        queues.queue(for: 0x05).async { out.fulfill() }

        wait(for: [out], timeout: 2.0)
        released.signal()

        XCTAssertFalse(queues.queue(for: 0x85) === queues.queue(for: 0x05))
    }

    // MARK: - One endpoint stays ordered

    /// The other half of the rule. A USB pipe is a FIFO, so transfers on a single
    /// endpoint must not overlap or reorder — the fix must not go so far as to run them
    /// concurrently.
    func testTransfersOnOneEndpointRunInOrder() {
        let queues = EndpointQueues()
        let lock = NSLock()
        var order: [Int] = []
        let done = expectation(description: "all five ran")
        done.expectedFulfillmentCount = 5

        for index in 0..<5 {
            queues.queue(for: 0x81).async {
                // A varying pause: a concurrent queue would let later, shorter work
                // overtake earlier work and scramble the recorded order.
                Thread.sleep(forTimeInterval: Double(5 - index) * 0.01)
                lock.lock()
                order.append(index)
                lock.unlock()
                done.fulfill()
            }
        }

        wait(for: [done], timeout: 5.0)
        XCTAssertEqual(order, [0, 1, 2, 3, 4])
    }

    /// Ordering above depends on one endpoint resolving to one queue every time.
    func testSameEndpointAlwaysGetsTheSameQueue() {
        let queues = EndpointQueues()
        XCTAssertTrue(queues.queue(for: 0x02) === queues.queue(for: 0x02))
    }

    /// Queues are made on demand from many threads at once, which is how a client with
    /// several endpoints in flight will first reach them. Two threads racing on one
    /// endpoint must still agree on a single queue, or ordering is lost.
    func testConcurrentFirstUseYieldsOneQueuePerEndpoint() {
        let queues = EndpointQueues()
        let lock = NSLock()
        var seen: [UInt8: Set<ObjectIdentifier>] = [:]

        DispatchQueue.concurrentPerform(iterations: 200) { iteration in
            let endpoint = UInt8(iteration % 4)
            let queue = queues.queue(for: endpoint)
            lock.lock()
            seen[endpoint, default: []].insert(ObjectIdentifier(queue))
            lock.unlock()
        }

        XCTAssertEqual(seen.count, 4)
        for (endpoint, identifiers) in seen {
            XCTAssertEqual(identifiers.count, 1, "endpoint \(endpoint) resolved to more than one queue")
        }
    }
}
