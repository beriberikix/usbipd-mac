// USBIPMessageFramerTests.swift
// The framer must reassemble split messages and separate coalesced ones, in order.

import XCTest
@testable import USBIPDCore

final class USBIPMessageFramerTests: XCTestCase {

    private func be32(_ value: UInt32) -> Data {
        var v = value.bigEndian
        return Data(bytes: &v, count: 4)
    }

    /// A CMD_SUBMIT as vhci_tx sends it: usbip_header_basic, then the fixed
    /// command block, then the transfer buffer for OUT.
    private func submit(
        seqnum: UInt32,
        devid: UInt32 = 0x0002_0001,
        direction: UInt32,
        ep: UInt32,
        payload: Data = Data(),
        transferLength: UInt32? = nil,
        packets: UInt32 = 0xffff_ffff,
        iso: Data = Data()
    ) -> Data {
        var m = Data()
        m += be32(1) + be32(seqnum) + be32(devid) + be32(direction) + be32(ep)   // basic, 20 bytes
        m += be32(0)                                                            // transfer_flags
        m += be32(transferLength ?? UInt32(payload.count))                      // transfer_buffer_length
        m += be32(0)                                                            // start_frame
        m += be32(packets)                                                      // number_of_packets
        m += be32(0)                                                            // interval
        m += Data(count: 8)                                                     // setup
        XCTAssertEqual(m.count, 48)
        return m + payload + iso
    }

    private func unlink(seqnum: UInt32, target: UInt32) -> Data {
        var m = Data()
        m += be32(2) + be32(seqnum) + be32(0x0002_0001) + be32(0) + be32(0)
        m += be32(target) + Data(count: 24)
        XCTAssertEqual(m.count, 48)
        return m
    }

    private func attached() -> USBIPConnectionState.Phase {
        let s = USBIPConnectionState()
        s.markAttached(busID: "2-1")
        return s.phase
    }

    func testTwoSubmitsInOneChunkAreBothFramedInOrder() throws {
        let out = submit(seqnum: 10, direction: 0, ep: 2, payload: Data([0xaa, 0x87]))
        let inp = submit(seqnum: 11, direction: 1, ep: 1, transferLength: 4096)
        let framer = USBIPMessageFramer()
        let messages = try framer.append(out + inp, phase: attached())
        XCTAssertEqual(messages, [out, inp])
        XCTAssertEqual(framer.pendingByteCount, 0)
    }

    func testSubmitSplitAcrossChunksIsReassembled() throws {
        let out = submit(seqnum: 12, direction: 0, ep: 2, payload: Data(repeating: 0x5a, count: 150))
        let framer = USBIPMessageFramer()
        XCTAssertEqual(try framer.append(out.prefix(30), phase: attached()), [])
        XCTAssertEqual(try framer.append(out.subdata(in: 30..<100), phase: attached()), [])
        XCTAssertEqual(framer.pendingByteCount, 100)
        XCTAssertEqual(try framer.append(out.subdata(in: 100..<out.count), phase: attached()), [out])
        XCTAssertEqual(framer.pendingByteCount, 0)
    }

    func testInSubmitCarriesNoPayloadEvenWithLargeTransferLength() throws {
        let inp = submit(seqnum: 13, direction: 1, ep: 1, transferLength: 4096)
        let next = unlink(seqnum: 14, target: 13)
        let framer = USBIPMessageFramer()
        XCTAssertEqual(try framer.append(inp + next, phase: attached()), [inp, next])
    }

    func testIsoDescriptorsAreCounted() throws {
        let iso = Data(repeating: 0x11, count: 3 * 16)
        let m = submit(seqnum: 15, direction: 1, ep: 3, transferLength: 3000, packets: 3, iso: iso)
        let framer = USBIPMessageFramer()
        XCTAssertEqual(try framer.append(m.prefix(50), phase: attached()), [])
        XCTAssertEqual(try framer.append(m.subdata(in: 50..<m.count), phase: attached()), [m])
    }

    func testHandshakeImportIsFortyBytesAndOnlyOneMessageIsReleased() throws {
        var imp = Data([0x01, 0x11, 0x80, 0x03, 0, 0, 0, 0])
        imp += "2-1".data(using: .ascii)! + Data(count: 29)
        XCTAssertEqual(imp.count, 40)
        let trailing = submit(seqnum: 1, direction: 1, ep: 1, transferLength: 64)
        let framer = USBIPMessageFramer()
        XCTAssertEqual(try framer.append(imp.prefix(8), phase: .handshake), [])
        XCTAssertEqual(try framer.append(imp.subdata(in: 8..<40) + trailing, phase: .handshake), [imp])
        XCTAssertEqual(framer.pendingByteCount, trailing.count)
        XCTAssertEqual(try framer.append(Data(), phase: attached()), [trailing])
    }

    func testDevlistIsEightBytes() throws {
        let devlist = Data([0x01, 0x11, 0x80, 0x05, 0, 0, 0, 0])
        XCTAssertEqual(try USBIPMessageFramer().append(devlist, phase: .handshake), [devlist])
    }

    func testUnknownCommandThrows() {
        let bogus = be32(99) + Data(count: 44)
        XCTAssertThrowsError(try USBIPMessageFramer().append(bogus, phase: attached()))
    }

    func testLaneKeysSeparateEndpointsDirectionsAndUnlinks() {
        let out = submit(seqnum: 1, direction: 0, ep: 2, payload: Data([1]))
        let out2 = submit(seqnum: 2, direction: 0, ep: 2, payload: Data([2]))
        let inp = submit(seqnum: 3, direction: 1, ep: 1, transferLength: 64)
        let cancel = unlink(seqnum: 4, target: 3)
        let phase = attached()
        XCTAssertEqual(ConnectionLanes.laneKey(for: out, phase: phase), ConnectionLanes.laneKey(for: out2, phase: phase))
        XCTAssertNotEqual(ConnectionLanes.laneKey(for: out, phase: phase), ConnectionLanes.laneKey(for: inp, phase: phase))
        XCTAssertEqual(ConnectionLanes.laneKey(for: cancel, phase: phase), ConnectionLanes.unlinkLane)
        XCTAssertEqual(ConnectionLanes.laneKey(for: out, phase: .handshake), ConnectionLanes.handshakeLane)
    }

    func testPipelineRunsSameLaneInOrderAndDifferentLanesConcurrently() {
        let state = USBIPConnectionState()
        state.markAttached(busID: "2-1")
        let inStarted = DispatchSemaphore(value: 0)
        let releaseIn = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var order: [UInt32] = []
        let pipeline = ConnectionReceivePipeline(state: state, label: "test", qos: .userInitiated,
            handler: { message in
                let seq = USBIPMessageFramer.be32(message, at: 4)
                if seq == 1 { inStarted.signal(); releaseIn.wait() }
                lock.lock(); order.append(seq); lock.unlock()
            },
            onFramingError: { XCTFail("unexpected framing error: \($0)") })

        let inp = submit(seqnum: 1, direction: 1, ep: 1, transferLength: 64)
        let out1 = submit(seqnum: 2, direction: 0, ep: 2, payload: Data([1]))
        let out2 = submit(seqnum: 3, direction: 0, ep: 2, payload: Data([2]))
        pipeline.receive(inp + out1 + out2)

        XCTAssertEqual(inStarted.wait(timeout: .now() + 2), .success)
        // Both OUTs complete while the IN is still blocked, in submission order.
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            lock.lock(); let done = order; lock.unlock()
            if done == [2, 3] { break }
            usleep(1000)
        }
        lock.lock(); XCTAssertEqual(order, [2, 3]); lock.unlock()
        releaseIn.signal()
        let end = Date().addingTimeInterval(2)
        while Date() < end {
            lock.lock(); let done = order; lock.unlock()
            if done.count == 3 { break }
            usleep(1000)
        }
        lock.lock(); XCTAssertEqual(order, [2, 3, 1]); lock.unlock()
    }
}
