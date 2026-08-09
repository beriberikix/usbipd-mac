// BoundDeviceStore.swift
// Which devices have been bound for sharing, kept apart from user configuration.

import Foundation
import Common

/// The list of devices `bind` has made available, persisted so it survives a restart.
///
/// This used to live in the configuration file alongside the port, the log level and
/// the transfer tuning, which was wrong in three ways.
///
/// The two have different owners. A port is chosen by a person and edited by hand; a
/// bind list is written by a command and read by a daemon. Holding them together meant
/// `bind` rewrote the whole configuration file to append one string, so a hand-edit
/// made between the CLI reading the file and writing it back was lost.
///
/// Worse, the CLI falls back to a default configuration when the file will not parse.
/// A single malformed character therefore turned the next `bind` into a silent reset of
/// the port and log level, with nothing but a warning on stderr to show for it. A
/// command that shares a USB device has no business rewriting unrelated settings, and
/// now it cannot: this file is the only thing bind and unbind touch.
///
/// The read-modify-write is also serialised. Appending to a list means reading it,
/// adding an entry and writing it back, and two `bind` commands doing that at once
/// would leave only one of the devices bound. Writes are atomic, so a reader never sees
/// a half-written file, but atomicity alone does not prevent a lost update.
public final class BoundDeviceStore {

    /// Contents of the state file. An object rather than a bare array so that fields
    /// can be added later — a bind timestamp, say — without changing the format.
    private struct State: Codable {
        var boundDevices: [String]
    }

    private let path: String

    /// Locking uses a file of its own, never the state file.
    ///
    /// Saving replaces the state file by renaming a new one over it, which leaves any
    /// lock held on the old file attached to an inode nobody else will open. Two writers
    /// could then hold "the lock" on two different files and both proceed. A lock file
    /// that is only ever created, never replaced, is the thing they can agree on.
    private let lockPath: String

    public init(path: String = BoundDeviceStore.defaultPath()) {
        self.path = path
        self.lockPath = path + ".lock"
    }

    /// Where the list is kept. Worth reporting in diagnostics, since the answer to
    /// "why is this device not shared" is usually in this file.
    public var filePath: String { path }

    /// `~/.usbipd/bound-devices.json`, beside the configuration but separate from it.
    public static func defaultPath() -> String {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(ServerConfig.defaultConfigDirName)
        return directory.appendingPathComponent("bound-devices.json").path
    }

    // MARK: - Reading

    /// The devices currently bound.
    ///
    /// No lock is taken. Writers replace this file by rename, so a reader sees either
    /// the whole previous version or the whole next one, and locking every read would
    /// put a system call in the path of every request for no benefit.
    public func boundDevices() -> [String] {
        guard let data = FileManager.default.contents(atPath: path) else {
            return migrateFromLegacyConfigIfNeeded()
        }
        guard let state = try? JSONDecoder().decode(State.self, from: data) else {
            return []
        }
        return state.boundDevices
    }

    public func isBound(_ busid: String) -> Bool {
        return boundDevices().contains(busid)
    }

    /// When the file last changed, for callers that cache the list.
    public func modificationDate() -> Date? {
        return try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }

    // MARK: - Writing

    /// Record a device as bound. Returns false if it already was.
    @discardableResult
    public func bind(_ busid: String) throws -> Bool {
        return try mutate { devices in
            guard !devices.contains(busid) else { return false }
            devices.append(busid)
            return true
        }
    }

    /// Forget a device. Returns false if it was not bound.
    @discardableResult
    public func unbind(_ busid: String) throws -> Bool {
        return try mutate { devices in
            guard let index = devices.firstIndex(of: busid) else { return false }
            devices.remove(at: index)
            return true
        }
    }

    /// Read, change and write back while holding an exclusive lock, so that two
    /// commands running at once cannot each write a list that omits the other's device.
    private func mutate(_ change: (inout [String]) -> Bool) throws -> Bool {
        try createDirectoryIfNeeded()

        let lock = try FileLock(path: lockPath)
        defer { lock.unlock() }
        lock.lock()

        var devices = boundDevices()
        guard change(&devices) else { return false }
        try write(devices)
        return true
    }

    private func write(_ devices: [String]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(State(boundDevices: devices))
        // Atomic, so a daemon reading concurrently never sees a partial list.
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func createDirectoryIfNeeded() throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Migration

    /// Adopt the list from a configuration file written before the two were separated.
    ///
    /// The old key is read but not removed. Rewriting the configuration file is the
    /// behaviour this change exists to stop, and a stale `allowedDevices` sitting in it
    /// is inert — nothing reads it any more.
    private func migrateFromLegacyConfigIfNeeded() -> [String] {
        let configPath = ServerConfig.defaultConfigPath()
        guard let data = FileManager.default.contents(atPath: configPath),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let legacy = object["allowedDevices"] as? [String],
              !legacy.isEmpty else {
            return []
        }

        // Best effort. Failing to write the new file simply means trying again next
        // time; the devices are still reported as bound either way.
        try? createDirectoryIfNeeded()
        try? write(legacy)
        return legacy
    }
}

/// An advisory lock on a file, held for as long as the object is.
private final class FileLock {
    private let descriptor: Int32

    init(path: String) throws {
        descriptor = open(path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else {
            throw ServerError.configurationError(
                "Could not open the lock file at \(path): \(String(cString: strerror(errno)))")
        }
    }

    func lock() {
        // Blocks until the other holder is done. The critical section is a small read
        // and write, so waiting is measured in microseconds.
        while flock(descriptor, LOCK_EX) != 0 && errno == EINTR { continue }
    }

    func unlock() {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
