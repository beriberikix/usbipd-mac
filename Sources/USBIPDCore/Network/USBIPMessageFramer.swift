// USBIPMessageFramer.swift
// Turns the TCP byte stream into whole USB/IP messages, and picks the queue each
// message runs on.

import Foundation

/// Splits the TCP byte stream into whole USB/IP messages.
///
/// A TCP read returns whatever bytes have arrived, not one message. Two commands
/// the client sent back-to-back arrive in one chunk, and a large command can arrive
/// in several. The receive handler used to pass each chunk to the processor as if it
/// were exactly one message, so the second command in a chunk was never decoded and
/// its URB never answered until the client gave up and unlinked it. Any driver that
/// keeps a read posted while it writes hit this on every transfer: hw_server's FTDI
/// JTAG driver submits a bulk OUT and the bulk IN for its reply a few microseconds
/// apart, and lost the IN every time.
///
/// Message length depends on the connection phase, because USB/IP changes framing
/// after OP_REQ_IMPORT with no in-band marker: op_common (8 bytes plus an op-specific
/// body) before, usbip_header_basic (48 bytes plus an optional payload) after.
public final class USBIPMessageFramer {

    public enum FramingError: Error, Equatable {
        case unknownOpCode(UInt16)
        case unknownCommand(UInt32)
        case oversizedMessage(Int)
    }

    /// op_common is version(2) code(2) status(4).
    public static let opCommonSize = 8
    /// OP_REQ_IMPORT carries a 32-byte busid after op_common.
    public static let importRequestSize = opCommonSize + 32
    /// usbip_header_basic plus the command-specific block, both fixed.
    public static let urbHeaderSize = 48
    /// One usbip_iso_packet_descriptor on the wire.
    public static let isoDescriptorSize = 16
    /// Largest message accepted: a header and the largest transfer buffer Linux
    /// will submit. Anything bigger is a corrupt stream, not a real request.
    public static let maxMessageSize = urbHeaderSize + 16 * 1024 * 1024

    private var buffer = Data()

    public init() {}

    /// Bytes held back because they do not yet form a whole message.
    public var pendingByteCount: Int { buffer.count }

    /// Appends `chunk` and returns every complete message now available, in the
    /// order the client sent them. Bytes of an incomplete trailing message stay
    /// buffered for the next call.
    ///
    /// In the handshake phase at most one message is returned, because the reply
    /// to it may switch the connection to URB framing; call again with an empty
    /// chunk once that reply has gone out to frame whatever followed.
    public func append(_ chunk: Data, phase: USBIPConnectionState.Phase) throws -> [Data] {
        buffer.append(chunk)
        var messages: [Data] = []
        while let length = try expectedLength(phase: phase), buffer.count >= length {
            messages.append(Data(buffer.prefix(length)))
            buffer = Data(buffer.dropFirst(length))
            if case .handshake = phase { break }
        }
        return messages
    }

    /// Length of the message at the head of the buffer, or nil while the header
    /// itself is still incomplete.
    private func expectedLength(phase: USBIPConnectionState.Phase) throws -> Int? {
        switch phase {
        case .handshake:
            guard buffer.count >= Self.opCommonSize else { return nil }
            let code = be16(at: 2)
            switch code {
            case USBIPMessageFramer.opReqDevlist: return Self.opCommonSize
            case USBIPMessageFramer.opReqImport: return Self.importRequestSize
            default: throw FramingError.unknownOpCode(code)
            }
        case .attached:
            guard buffer.count >= Self.urbHeaderSize else { return nil }
            let command = be32(at: 0)
            switch command {
            case USBIPMessageFramer.cmdSubmit:
                // direction 0 is OUT, whose transfer buffer follows the header.
                // ISO descriptors follow in either direction; number_of_packets is
                // 0xffffffff (or 0) for everything that is not isochronous.
                let direction = be32(at: 12)
                let transferLength = Int(be32(at: 24))
                let packets = be32(at: 32)
                let isoBytes = packets == 0xffff_ffff ? 0 : Int(packets) * Self.isoDescriptorSize
                let total = Self.urbHeaderSize + (direction == 0 ? transferLength : 0) + isoBytes
                guard total <= Self.maxMessageSize else { throw FramingError.oversizedMessage(total) }
                return total
            case USBIPMessageFramer.cmdUnlink:
                return Self.urbHeaderSize
            default:
                throw FramingError.unknownCommand(command)
            }
        }
    }

    static let opReqImport: UInt16 = 0x8003
    static let opReqDevlist: UInt16 = 0x8005
    static let cmdSubmit: UInt32 = 1
    static let cmdUnlink: UInt32 = 2

    private func be16(at offset: Int) -> UInt16 {
        USBIPMessageFramer.be16(buffer, at: offset)
    }

    private func be32(at offset: Int) -> UInt32 {
        USBIPMessageFramer.be32(buffer, at: offset)
    }

    static func be16(_ data: Data, at offset: Int) -> UInt16 {
        let i = data.startIndex + offset
        return UInt16(data[i]) << 8 | UInt16(data[i + 1])
    }

    static func be32(_ data: Data, at offset: Int) -> UInt32 {
        let i = data.startIndex + offset
        return UInt32(data[i]) << 24 | UInt32(data[i + 1]) << 16 | UInt32(data[i + 2]) << 8 | UInt32(data[i + 3])
    }
}

/// Hands out one serial queue per lane, where a lane is one endpoint in one
/// direction on one device.
///
/// The request processor blocks its thread until IOKit finishes the transfer, so
/// messages cannot all share one serial queue: a pending bulk IN would hold every
/// later command, including the OUT that produces the data it is waiting for. They
/// cannot share a concurrent queue either: two writes to one endpoint could reach
/// the pipe in the wrong order, and a pipe is a FIFO the client expects to be
/// honoured. Serial per lane gives both properties. Unlinks get a lane of their own
/// because an unlink must run while the transfer it cancels is still blocking.
public final class ConnectionLanes {

    public static let handshakeLane = "handshake"
    public static let unlinkLane = "unlink"

    private var lanes: [String: DispatchQueue] = [:]
    private let lock = NSLock()
    private let label: String
    private let qos: DispatchQoS

    public init(label: String, qos: DispatchQoS) {
        self.label = label
        self.qos = qos
    }

    /// The lane a framed message belongs to.
    public static func laneKey(for message: Data, phase: USBIPConnectionState.Phase) -> String {
        if case .handshake = phase { return handshakeLane }
        let command = USBIPMessageFramer.be32(message, at: 0)
        guard command == USBIPMessageFramer.cmdSubmit else { return unlinkLane }
        let devid = USBIPMessageFramer.be32(message, at: 8)
        let direction = USBIPMessageFramer.be32(message, at: 12)
        let endpoint = USBIPMessageFramer.be32(message, at: 16)
        return "\(devid):\(endpoint):\(direction)"
    }

    public func queue(for key: String) -> DispatchQueue {
        lock.lock()
        defer { lock.unlock() }
        if let existing = lanes[key] {
            return existing
        }
        let created = DispatchQueue(label: "\(label).\(key)", qos: qos)
        lanes[key] = created
        return created
    }
}

/// One connection's receive path: frame the bytes, then run each message on its lane.
public final class ConnectionReceivePipeline {

    private let framer = USBIPMessageFramer()
    private let lanes: ConnectionLanes
    private let framingQueue: DispatchQueue
    private let state: USBIPConnectionState
    private let handler: (Data) -> Void
    private let onFramingError: (Error) -> Void
    private let onFramed: ((Data) -> Void)?

    /// - Parameters:
    ///   - state: the connection's phase, read at framing time.
    ///   - handler: processes one whole message; may block until the transfer completes.
    ///   - onFramingError: the stream cannot be framed; the caller should close it.
    ///   - onFramed: sees each message in wire order, before it is queued on its lane.
    ///     Must not block.
    public init(state: USBIPConnectionState,
                label: String,
                qos: DispatchQoS,
                handler: @escaping (Data) -> Void,
                onFramingError: @escaping (Error) -> Void,
                onFramed: ((Data) -> Void)? = nil) {
        self.state = state
        self.lanes = ConnectionLanes(label: "com.usbipd.lane.\(label)", qos: qos)
        self.framingQueue = DispatchQueue(label: "com.usbipd.framing.\(label)")
        self.handler = handler
        self.onFramingError = onFramingError
        self.onFramed = onFramed
    }

    /// Accepts a chunk from the socket. Safe to call from any thread.
    public func receive(_ chunk: Data) {
        framingQueue.async { self.frame(chunk) }
    }

    private func frame(_ chunk: Data) {
        let phase = state.phase
        let messages: [Data]
        do {
            messages = try framer.append(chunk, phase: phase)
        } catch {
            onFramingError(error)
            return
        }
        for message in messages {
            let key = ConnectionLanes.laneKey(for: message, phase: phase)
            // A lane runs one message at a time, so a request can wait behind a
            // blocking transfer on the same endpoint while its UNLINK, on the unlink
            // lane, runs straight away. Registered here, in wire order, the request
            // exists by the time anything can cancel it.
            onFramed?(message)
            lanes.queue(for: key).async {
                self.handler(message)
                if key == ConnectionLanes.handshakeLane {
                    // The reply may have moved the connection to URB framing, so
                    // frame whatever arrived behind this message under the new phase.
                    self.receive(Data())
                }
            }
        }
    }
}
