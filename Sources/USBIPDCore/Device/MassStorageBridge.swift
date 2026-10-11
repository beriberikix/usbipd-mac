// MassStorageBridge.swift
// Serves a USB mass-storage interface to a client from the disk macOS made of it.

import Foundation
import Common

/// Storage a bridged mass-storage interface reads and writes.
protocol BlockDevice: AnyObject {
    var blockSize: UInt32 { get }
    var blockCount: UInt64 { get }
    var isWritable: Bool { get }
    func read(lba: UInt64, blocks: UInt32) throws -> Data
    func write(lba: UInt64, data: Data) throws
    func synchronize() throws
}

enum BlockDeviceError: Error {
    case io(Int32)
    case outOfRange
}

/// A whole disk opened raw: `/dev/rdiskN`.
final class RawDiskBlockDevice: BlockDevice {
    let blockSize: UInt32
    let blockCount: UInt64
    let isWritable: Bool
    private let fd: Int32

    // DKIOCGETBLOCKSIZE and DKIOCGETBLOCKCOUNT, <sys/disk.h>: _IOR('d', 24, uint32_t)
    // and _IOR('d', 25, uint64_t). The macros do not import into Swift.
    private static let getBlockSize: UInt = 0x4004_6418
    private static let getBlockCount: UInt = 0x4008_6419

    init(path: String) throws {
        var descriptor = open(path, O_RDWR)
        var writable = true
        if descriptor < 0 {
            descriptor = open(path, O_RDONLY)
            writable = false
        }
        guard descriptor >= 0 else { throw BlockDeviceError.io(errno) }

        var size: UInt32 = 0
        var count: UInt64 = 0
        guard ioctl(descriptor, Self.getBlockSize, &size) == 0,
              ioctl(descriptor, Self.getBlockCount, &count) == 0,
              size > 0 else {
            let error = errno
            close(descriptor)
            throw BlockDeviceError.io(error)
        }
        fd = descriptor
        blockSize = size
        blockCount = count
        isWritable = writable
    }

    deinit {
        close(fd)
    }

    func read(lba: UInt64, blocks: UInt32) throws -> Data {
        guard lba + UInt64(blocks) <= blockCount else { throw BlockDeviceError.outOfRange }
        let length = Int(blocks) * Int(blockSize)
        var buffer = Data(count: length)
        let done = buffer.withUnsafeMutableBytes { bytes in
            pread(fd, bytes.baseAddress, length, off_t(lba) * off_t(blockSize))
        }
        guard done == length else { throw BlockDeviceError.io(done < 0 ? errno : EIO) }
        return buffer
    }

    func write(lba: UInt64, data: Data) throws {
        let blocks = UInt64(data.count) / UInt64(blockSize)
        guard lba + blocks <= blockCount else { throw BlockDeviceError.outOfRange }
        let done = data.withUnsafeBytes { bytes in
            pwrite(fd, bytes.baseAddress, data.count, off_t(lba) * off_t(blockSize))
        }
        guard done == data.count else { throw BlockDeviceError.io(done < 0 ? errno : EIO) }
    }

    func synchronize() throws {
        guard fsync(fd) == 0 else { throw BlockDeviceError.io(errno) }
    }
}

/// The device side of USB Bulk-Only Transport, answering SCSI from a block device.
///
/// A mass-storage interface cannot be handed to a client the way the others are. Its
/// driver survives capture — IOUSBLib.h says so, and it was measured — and asking for a
/// user client on it, captured or not, either blocks in the kernel indefinitely or is
/// refused, depending on which process asks and when. So the interface is never opened
/// at all. macOS keeps driving the hardware; the volume is unmounted so nothing on this
/// side touches it; and the client's commands are answered here, from the raw disk.
///
/// What crosses the wire is ordinary SCSI over BOT, so the client binds usb-storage and
/// gets a real block device: reads and writes land on the hardware as they would plugged
/// in. That is what a UF2 loader — an RP2040 in BOOTSEL, a FreeWili's FBL drive — acts on.
///
/// Thread-safe: the client's IN and OUT endpoints run on separate lanes.
final class MassStorageBridge: @unchecked Sendable {

    let inEndpoint: UInt8
    let outEndpoint: UInt8

    /// Nil when the drive has no medium — a card reader with no card.
    private let device: BlockDevice?
    private let vendor: String
    private let product: String

    /// SCSI sense: key, additional sense code and qualifier.
    private struct Sense: Equatable {
        let key: UInt8
        let asc: UInt8
        let ascq: UInt8

        static let none = Sense(key: 0x00, asc: 0x00, ascq: 0x00)
        static let notReadyNoMedium = Sense(key: 0x02, asc: 0x3A, ascq: 0x00)
        static let invalidOpcode = Sense(key: 0x05, asc: 0x20, ascq: 0x00)
        static let lbaOutOfRange = Sense(key: 0x05, asc: 0x21, ascq: 0x00)
        static let invalidFieldInCDB = Sense(key: 0x05, asc: 0x24, ascq: 0x00)
        static let unrecoveredReadError = Sense(key: 0x03, asc: 0x11, ascq: 0x00)
        static let writeError = Sense(key: 0x03, asc: 0x0C, ascq: 0x00)
        static let writeProtected = Sense(key: 0x07, asc: 0x27, ascq: 0x00)
    }

    /// A write in progress: where the next whole block goes, and what is still owed.
    private struct PendingWrite {
        var lba: UInt64
        let expected: Int
        var received: Int
        var pending: Data
        let tag: UInt32
        var failed: Bool
    }

    private enum Phase {
        case command
        case dataIn(Data, sent: Int, status: Data)
        case dataOut(PendingWrite)
        case status(Data)
    }

    private var phase: Phase = .command
    private var sense = Sense.none
    private var cancelGeneration = 0
    private let condition = NSCondition()

    init(inEndpoint: UInt8, outEndpoint: UInt8, device: BlockDevice?, vendor: String, product: String) {
        self.inEndpoint = inEndpoint
        self.outEndpoint = outEndpoint
        self.device = device
        self.vendor = vendor
        self.product = product
    }

    // MARK: - Transport

    /// Bulk OUT: a command block, or data for the write it announced.
    func receive(_ data: Data) {
        condition.lock()
        defer { condition.unlock() }

        if case let .dataOut(write) = phase {
            acceptWriteData(data, into: write)
        } else {
            execute(commandBlock: data)
        }
        condition.broadcast()
    }

    /// Bulk IN: response data, then the status. Nil if nothing is due before `deadline`,
    /// or the read was cancelled.
    func send(maxLength: Int, deadline: Date) -> Data? {
        condition.lock()
        defer { condition.unlock() }

        let generation = cancelGeneration
        while true {
            switch phase {
            case let .dataIn(data, sent, status):
                let chunk = data.subdata(in: sent..<min(data.count, sent + maxLength))
                let nowSent = sent + chunk.count
                // A short read ends the data phase, as a short packet does on the bus.
                if nowSent >= data.count || chunk.count < maxLength {
                    phase = .status(status)
                } else {
                    phase = .dataIn(data, sent: nowSent, status: status)
                }
                return chunk

            case let .status(status):
                phase = .command
                return status

            case .command, .dataOut:
                guard cancelGeneration == generation, condition.wait(until: deadline) else { return nil }
                guard cancelGeneration == generation else { return nil }
            }
        }
    }

    /// Release any read waiting in `send`.
    func cancelPendingReads() {
        condition.lock()
        cancelGeneration += 1
        condition.broadcast()
        condition.unlock()
    }

    /// Bulk-Only Mass Storage Reset: drop whatever command was in progress.
    func reset() {
        condition.lock()
        phase = .command
        cancelGeneration += 1
        condition.broadcast()
        condition.unlock()
    }

    // MARK: - Commands

    private func execute(commandBlock data: Data) {
        let cbw = [UInt8](data)
        // "USBC", little-endian. Anything else is not a command; the host will time out
        // and reset, which is the recovery BOT defines.
        guard cbw.count >= 31, cbw[0] == 0x55, cbw[1] == 0x53, cbw[2] == 0x42, cbw[3] == 0x43 else {
            return
        }
        let tag = le32(cbw, 4)
        let length = Int(le32(cbw, 8))
        let toHost = (cbw[12] & 0x80) != 0
        let cdb = Array(cbw[15..<(15 + Int(min(cbw[14], 16)))])
        guard let opcode = cdb.first else {
            finish(tag: tag, length: length, toHost: toHost, failWith: .invalidOpcode)
            return
        }

        switch opcode {
        case 0x00: // TEST UNIT READY
            finish(tag: tag, length: length, toHost: toHost, failWith: device == nil ? Sense.notReadyNoMedium : nil)
        case 0x03: // REQUEST SENSE
            var fixed = [UInt8](repeating: 0, count: 18)
            fixed[0] = 0x70
            fixed[2] = sense.key
            fixed[7] = 10
            fixed[12] = sense.asc
            fixed[13] = sense.ascq
            sense = .none
            respond(tag: tag, length: length, data: fixed.prefix(Int(cdb.count > 4 ? cdb[4] : 18)))
        case 0x12: // INQUIRY
            if cdb.count > 1 && (cdb[1] & 0x01) != 0 {
                finish(tag: tag, length: length, toHost: toHost, failWith: .invalidFieldInCDB)
                return
            }
            var inquiry: [UInt8] = [0x00, 0x80, 0x04, 0x02, 31, 0, 0, 0]
            inquiry += padded(vendor, 8) + padded(product, 16) + padded("1.00", 4)
            respond(tag: tag, length: length, data: inquiry.prefix(allocation(cdb, at: 3, width: 2)))
        case 0x1A: // MODE SENSE(6)
            let header: [UInt8] = [3, 0, writeProtect, 0]
            respond(tag: tag, length: length, data: header.prefix(Int(cdb.count > 4 ? cdb[4] : 4)))
        case 0x5A: // MODE SENSE(10)
            let header: [UInt8] = [0, 6, 0, writeProtect, 0, 0, 0, 0]
            respond(tag: tag, length: length, data: header.prefix(allocation(cdb, at: 7, width: 2)))
        case 0x1B, 0x1E, 0x2F, 0x35: // START STOP, PREVENT ALLOW, VERIFY, SYNCHRONIZE CACHE
            if opcode == 0x35 { try? device?.synchronize() }
            finish(tag: tag, length: length, toHost: toHost, failWith: nil)
        case 0x23: // READ FORMAT CAPACITIES
            guard let device = device else {
                finish(tag: tag, length: length, toHost: toHost, failWith: .notReadyNoMedium)
                return
            }
            var list: [UInt8] = [0, 0, 0, 8]
            list += be32(UInt32(clamping: device.blockCount)) + [0x02] + Array(be32(device.blockSize).suffix(3))
            respond(tag: tag, length: length, data: list.prefix(allocation(cdb, at: 7, width: 2)))
        case 0x25: // READ CAPACITY(10)
            guard let device = device else {
                finish(tag: tag, length: length, toHost: toHost, failWith: .notReadyNoMedium)
                return
            }
            let last = UInt32(clamping: device.blockCount &- 1)
            respond(tag: tag, length: length, data: be32(last) + be32(device.blockSize))
        case 0x9E where cdb.count > 1 && (cdb[1] & 0x1F) == 0x10: // READ CAPACITY(16)
            guard let device = device else {
                finish(tag: tag, length: length, toHost: toHost, failWith: .notReadyNoMedium)
                return
            }
            var capacity = be64(device.blockCount &- 1) + be32(device.blockSize)
            capacity += [UInt8](repeating: 0, count: 20)
            respond(tag: tag, length: length, data: capacity.prefix(allocation(cdb, at: 10, width: 4)))
        case 0x28, 0xA8, 0x88: // READ(10), READ(12), READ(16)
            let (lba, blocks) = addressing(cdb)
            guard let device = device else {
                finish(tag: tag, length: length, toHost: toHost, failWith: .notReadyNoMedium)
                return
            }
            do {
                respond(tag: tag, length: length, data: try device.read(lba: lba, blocks: blocks))
            } catch BlockDeviceError.outOfRange {
                finish(tag: tag, length: length, toHost: toHost, failWith: .lbaOutOfRange)
            } catch {
                finish(tag: tag, length: length, toHost: toHost, failWith: .unrecoveredReadError)
            }
        case 0x2A, 0xAA, 0x8A: // WRITE(10), WRITE(12), WRITE(16)
            let (lba, _) = addressing(cdb)
            let failure: Sense? = device == nil ? .notReadyNoMedium
                : (device?.isWritable == false ? .writeProtected : nil)
            if let failure = failure { sense = failure }
            if length == 0 {
                phase = .status(csw(tag: tag, residue: 0, failed: failure != nil))
            } else {
                phase = .dataOut(PendingWrite(lba: lba, expected: length, received: 0, pending: Data(),
                                              tag: tag, failed: failure != nil))
            }
        default:
            finish(tag: tag, length: length, toHost: toHost, failWith: .invalidOpcode)
        }
    }

    private func acceptWriteData(_ data: Data, into write: PendingWrite) {
        var write = write
        write.pending += data
        write.received += data.count

        // Write whole blocks as they arrive rather than holding the whole transfer.
        if !write.failed, let device = device {
            let blockSize = Int(device.blockSize)
            let whole = (write.pending.count / blockSize) * blockSize
            if whole > 0 {
                do {
                    try device.write(lba: write.lba, data: write.pending.prefix(whole))
                    write.lba += UInt64(whole / blockSize)
                    write.pending = write.pending.subdata(in: whole..<write.pending.count)
                } catch {
                    write.failed = true
                    sense = .writeError
                }
            }
        }

        if write.received >= write.expected {
            phase = .status(csw(tag: write.tag, residue: 0, failed: write.failed))
        } else {
            phase = .dataOut(write)
        }
    }

    /// Answer a command that returns data. The client asked for `length`; less is a
    /// short transfer and the difference is the residue.
    private func respond<C: Collection>(tag: UInt32, length: Int, data: C) where C.Element == UInt8 {
        let payload = Data(data.prefix(length))
        let status = csw(tag: tag, residue: UInt32(length - payload.count), failed: false)
        phase = length == 0 ? .status(status) : .dataIn(payload, sent: 0, status: status)
    }

    /// A command with no data of its own. On failure the data phase the client expects
    /// still happens — empty for IN, drained for OUT — before a failed status.
    private func finish(tag: UInt32, length: Int, toHost: Bool, failWith failure: Sense?) {
        if let failure = failure {
            sense = failure
        }
        let status = csw(tag: tag, residue: UInt32(length), failed: failure != nil)
        if length == 0 {
            phase = .status(status)
        } else if toHost {
            phase = .dataIn(Data(), sent: 0, status: status)
        } else {
            phase = .dataOut(PendingWrite(lba: 0, expected: length, received: 0, pending: Data(), tag: tag, failed: true))
        }
    }

    // MARK: - Encoding

    private var writeProtect: UInt8 { device?.isWritable == false ? 0x80 : 0 }

    private func csw(tag: UInt32, residue: UInt32, failed: Bool) -> Data {
        return Data([0x55, 0x53, 0x42, 0x53] + le32bytes(tag) + le32bytes(residue) + [failed ? 1 : 0])
    }

    private func addressing(_ cdb: [UInt8]) -> (UInt64, UInt32) {
        func be(_ start: Int, _ width: Int) -> UInt64 {
            guard cdb.count >= start + width else { return 0 }
            return cdb[start..<(start + width)].reduce(0) { $0 << 8 | UInt64($1) }
        }
        switch cdb[0] {
        case 0x28, 0x2A: return (be(2, 4), UInt32(be(7, 2)))
        case 0xA8, 0xAA: return (be(2, 4), UInt32(be(6, 4)))
        default: return (be(2, 8), UInt32(be(10, 4)))
        }
    }

    private func allocation(_ cdb: [UInt8], at start: Int, width: Int) -> Int {
        guard cdb.count >= start + width else { return 0 }
        return Int(cdb[start..<(start + width)].reduce(0) { $0 << 8 | UInt32($1) })
    }

    private func padded(_ text: String, _ width: Int) -> [UInt8] {
        let ascii = Array(text.utf8.filter { $0 >= 0x20 && $0 < 0x7F }.prefix(width))
        return ascii + [UInt8](repeating: 0x20, count: width - ascii.count)
    }

    private func le32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    private func le32bytes(_ value: UInt32) -> [UInt8] {
        return [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24)]
    }

    private func be32(_ value: UInt32) -> [UInt8] {
        return [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    private func be64(_ value: UInt64) -> [UInt8] {
        return be32(UInt32(value >> 32)) + be32(UInt32(value & 0xFFFF_FFFF))
    }
}
