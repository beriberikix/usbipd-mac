// MassStorageBridgeTests.swift
// Bulk-Only Transport and SCSI, answered from a block device.

import XCTest
@testable import USBIPDCore

private final class MemoryDisk: BlockDevice {
    let blockSize: UInt32 = 512
    let blockCount: UInt64
    let isWritable: Bool
    var bytes: [UInt8]

    init(blocks: UInt64, writable: Bool = true) {
        blockCount = blocks
        isWritable = writable
        bytes = [UInt8](repeating: 0, count: Int(blocks) * 512)
    }

    func read(lba: UInt64, blocks: UInt32) throws -> Data {
        guard lba + UInt64(blocks) <= blockCount else { throw BlockDeviceError.outOfRange }
        let start = Int(lba) * 512
        return Data(bytes[start..<(start + Int(blocks) * 512)])
    }

    func write(lba: UInt64, data: Data) throws {
        guard lba + UInt64(data.count / 512) <= blockCount else { throw BlockDeviceError.outOfRange }
        let start = Int(lba) * 512
        bytes.replaceSubrange(start..<(start + data.count), with: data)
    }

    func synchronize() throws {}
}

final class MassStorageBridgeTests: XCTestCase {

    private func cbw(tag: UInt32, length: UInt32, toHost: Bool, _ cdb: [UInt8]) -> Data {
        var block: [UInt8] = [0x55, 0x53, 0x42, 0x43]
        block += withUnsafeBytes(of: tag.littleEndian, Array.init)
        block += withUnsafeBytes(of: length.littleEndian, Array.init)
        block += [toHost ? 0x80 : 0x00, 0, UInt8(cdb.count)]
        block += cdb + [UInt8](repeating: 0, count: 16 - cdb.count)
        return Data(block)
    }

    private func read(_ bridge: MassStorageBridge, _ length: Int = 512) -> Data? {
        return bridge.send(maxLength: length, deadline: Date().addingTimeInterval(1))
    }

    /// Status wrapper: signature, tag, residue, status.
    private func assertStatus(
        _ data: Data?,
        tag: UInt32,
        residue: UInt32 = 0,
        failed: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let bytes = data.map(Array.init), bytes.count == 13 else {
            return XCTFail("expected a 13-byte CSW, got \(String(describing: data))", file: file, line: line)
        }
        XCTAssertEqual(Array(bytes[0..<4]), [0x55, 0x53, 0x42, 0x53], file: file, line: line)
        XCTAssertEqual(bytes[4..<8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }, tag, file: file, line: line)
        XCTAssertEqual(bytes[8..<12].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }, residue, file: file, line: line)
        XCTAssertEqual(bytes[12], failed ? 1 : 0, file: file, line: line)
    }

    func testInquiryAnswersThenReportsStatus() {
        let bridge = MassStorageBridge(inEndpoint: 0x81, outEndpoint: 0x02, device: MemoryDisk(blocks: 64),
                                       vendor: "RPI", product: "RP2")
        bridge.receive(cbw(tag: 7, length: 36, toHost: true, [0x12, 0, 0, 0, 36, 0]))

        let inquiry = read(bridge)
        XCTAssertEqual(inquiry?.count, 36)
        XCTAssertEqual(inquiry.map { Array($0[8..<11]) }, Array("RPI".utf8))
        assertStatus(read(bridge), tag: 7)
    }

    func testReadCapacityReportsTheLastBlock() {
        let bridge = MassStorageBridge(inEndpoint: 0x81, outEndpoint: 0x02, device: MemoryDisk(blocks: 64),
                                       vendor: "", product: "")
        bridge.receive(cbw(tag: 1, length: 8, toHost: true, [0x25, 0, 0, 0, 0, 0, 0, 0, 0, 0]))

        XCTAssertEqual(read(bridge).map(Array.init), [0, 0, 0, 63, 0, 0, 2, 0])
        assertStatus(read(bridge), tag: 1)
    }

    /// Data for a write arrives in pieces that do not line up with blocks. What lands on
    /// the disk must be exactly what was sent, and reads back the same.
    func testWriteSplitAcrossChunksReadsBackIntact() {
        let disk = MemoryDisk(blocks: 64)
        let bridge = MassStorageBridge(inEndpoint: 0x81, outEndpoint: 0x02, device: disk, vendor: "", product: "")
        let payload = Data((0..<1024).map { UInt8($0 & 0xFF) ^ 0x5A })

        bridge.receive(cbw(tag: 2, length: 1024, toHost: false, [0x2A, 0, 0, 0, 0, 3, 0, 0, 2, 0]))
        bridge.receive(payload.subdata(in: 0..<300))
        bridge.receive(payload.subdata(in: 300..<800))
        bridge.receive(payload.subdata(in: 800..<1024))
        assertStatus(read(bridge), tag: 2)
        XCTAssertEqual(Data(disk.bytes[1536..<2560]), payload)

        bridge.receive(cbw(tag: 3, length: 1024, toHost: true, [0x28, 0, 0, 0, 0, 3, 0, 0, 2, 0]))
        var back = Data()
        while back.count < 1024, let chunk = read(bridge, 512) { back += chunk }
        XCTAssertEqual(back, payload)
        assertStatus(read(bridge), tag: 3)
    }

    /// A card reader with no card: present, answers INQUIRY, reports no medium.
    func testNoMediumIsReportedAsNotReady() {
        let bridge = MassStorageBridge(inEndpoint: 0x81, outEndpoint: 0x02, device: nil, vendor: "", product: "")
        bridge.receive(cbw(tag: 4, length: 0, toHost: false, [0x00, 0, 0, 0, 0, 0]))
        assertStatus(read(bridge), tag: 4, failed: true)

        bridge.receive(cbw(tag: 5, length: 18, toHost: true, [0x03, 0, 0, 0, 18, 0]))
        let sense = read(bridge).map(Array.init)
        XCTAssertEqual(sense?[2], 0x02, "sense key NOT READY")
        XCTAssertEqual(sense?[12], 0x3A, "MEDIUM NOT PRESENT")
        assertStatus(read(bridge), tag: 5)
    }

    /// An unsupported command that expected data still gets its data phase — empty —
    /// before a failed status, or the client's IN transfer would wait for nothing.
    func testUnsupportedCommandFailsWithFullResidue() {
        let bridge = MassStorageBridge(inEndpoint: 0x81, outEndpoint: 0x02, device: MemoryDisk(blocks: 8),
                                       vendor: "", product: "")
        bridge.receive(cbw(tag: 6, length: 64, toHost: true, [0xFF, 0, 0, 0, 0, 0]))
        XCTAssertEqual(read(bridge)?.count, 0)
        assertStatus(read(bridge), tag: 6, residue: 64, failed: true)
    }

    /// A read with nothing to report waits, and a cancel releases it.
    func testIdleReadWaitsAndCancelReleasesIt() {
        let bridge = MassStorageBridge(inEndpoint: 0x81, outEndpoint: 0x02, device: MemoryDisk(blocks: 8),
                                       vendor: "", product: "")
        XCTAssertNil(bridge.send(maxLength: 13, deadline: Date().addingTimeInterval(0.1)))

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { bridge.cancelPendingReads() }
        let started = Date()
        XCTAssertNil(bridge.send(maxLength: 13, deadline: Date().addingTimeInterval(5)))
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }
}
