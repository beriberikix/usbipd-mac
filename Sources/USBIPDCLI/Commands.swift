// Commands.swift
// Implementation of CLI commands for USB/IP daemon

import Foundation
import USBIPDCore
import Common

// Logger for command operations
private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "cli-commands")

/// Command handler error types
public enum CommandHandlerError: Error, LocalizedError {
    case deviceBindingFailed(String)
    case deviceUnbindingFailed(String)
    case deviceAttachmentFailed(String)
    case deviceDetachmentFailed(String)
    case serverStartFailed(String)
    case serverStopFailed(String)
    case deviceNotFound(String)
    case operationNotSupported(String)
    
    public var errorDescription: String? {
        switch self {
        case .deviceBindingFailed(let msg):
            return "Device binding failed: \(msg)"
        case .deviceUnbindingFailed(let msg):
            return "Device unbinding failed: \(msg)"
        case .deviceAttachmentFailed(let msg):
            return "Device attachment failed: \(msg)"
        case .deviceDetachmentFailed(let msg):
            return "Device detachment failed: \(msg)"
        case .serverStartFailed(let msg):
            return "Server start failed: \(msg)"
        case .serverStopFailed(let msg):
            return "Server stop failed: \(msg)"
        case .deviceNotFound(let msg):
            return "Device not found: \(msg)"
        case .operationNotSupported(let msg):
            return "Operation not supported: \(msg)"
        }
    }
}

/// Help command implementation
public class HelpCommand: Command {
    public let name = "help"
    public let description = "Display help information"
    
    private weak var parser: CommandLineParser?
    
    init(parser: CommandLineParser) {
        self.parser = parser
    }
    
    public func execute(with arguments: [String]) throws {
        logger.debug("Executing help command")
        
        print("USB/IP Daemon for macOS")
        print("Version: \(USBIPDVersion.current)")
        print("")
        print("Usage: usbipd [command] [options]")
        print("")
        print("Commands:")
        
        guard let commands = parser?.getCommands() else {
            logger.warning("Parser reference is nil, cannot display commands")
            return
        }
        
        // Sort commands alphabetically for consistent display
        let sortedCommands = commands.sorted { $0.name < $1.name }
        
        for command in sortedCommands {
            print("  \(command.name.padding(toLength: 10, withPad: " ", startingAt: 0)) \(command.description)")
        }
        
        logger.debug("Help command executed successfully")
    }
}

/// List command implementation
public class ListCommand: Command {
    public let name = "list"
    public let description = "List available USB devices"
    
    private let deviceDiscovery: DeviceDiscovery
    private let outputFormatter: OutputFormatter
    
    public init(deviceDiscovery: DeviceDiscovery, outputFormatter: OutputFormatter = DefaultOutputFormatter()) {
        self.deviceDiscovery = deviceDiscovery
        self.outputFormatter = outputFormatter
    }
    
    public func execute(with arguments: [String]) throws {
        logger.debug("Executing list command", context: ["arguments": arguments.joined(separator: " ")])
        
        // Parse options
        var showRemoteOnly = false
        
        for arg in arguments {
            switch arg {
            case "-l", "--local":
                logger.debug("Using local device listing mode (default)")
                // Local is the default, so we don't need to do anything
                break
            case "-r", "--remote":
                logger.debug("Using remote device listing mode")
                showRemoteOnly = true
            case "-h", "--help":
                logger.debug("Showing help for list command")
                printHelp()
                return
            default:
                logger.error("Unknown option for list command", context: ["option": arg])
                throw CommandLineError.invalidArguments("Unknown option: \(arg)")
            }
        }
        
        // For MVP, we only support local devices
        if showRemoteOnly {
            logger.warning("Remote device listing requested but not supported")
            print("Remote device listing is not supported in this version")
            return
        }
        
        do {
            logger.debug("Discovering USB devices")
            // Get devices from device discovery
            let devices = try deviceDiscovery.discoverDevices()
            
            logger.info("Found \(devices.count) USB devices")
            
            // Format and print the device list
            let formattedOutput = outputFormatter.formatDeviceList(devices)
            print(formattedOutput)
            
            if devices.isEmpty {
                // The formatter already emits this line; printing it here too showed it
                // twice.
                logger.info("No USB devices found")
            }
            
            logger.debug("List command executed successfully")
        } catch {
            logger.error("Failed to list devices", context: ["error": error.localizedDescription])
            print("Error: Failed to list devices: \(error.localizedDescription)")
            throw CommandLineError.executionFailed("Failed to list devices: \(error.localizedDescription)")
        }
    }
    
    private func printHelp() {
        print("Usage: usbipd list [options]")
        print("")
        print("Options:")
        print("  -l, --local     Show local devices only (default)")
        print("  -r, --remote    Show remote devices only (not supported in this version)")
        print("  -h, --help      Show this help message")
    }
}

/// How a bind or unbind was carried out.
private enum BindOutcome {
    /// A running daemon applied it and confirmed. `changed` is false when the device
    /// was already in that state.
    case daemon(changed: Bool)
    /// No daemon was listening, so the state file was written directly. It will be read
    /// when a daemon next starts.
    case directly(changed: Bool)
}

/// Apply a change to the bound-device list, preferring a running daemon.
///
/// Asking the daemon is what lets these commands report what actually happened. Writing
/// the file and leaving the daemon to notice meant `bind` could only report that it had
/// written a file — and for a long time it did not even mean that much, because the
/// daemon read the file once at startup and never again.
///
/// Falling back to a direct write keeps the first run working: binding a device before
/// the daemon has ever been started is ordinary, and refusing it would be worse than
/// doing it quietly.
private func applyBinding(_ command: ControlRequest.Command,
                          busid: String,
                          store: BoundDeviceStore) throws -> BindOutcome {
    if let response = ControlSocketClient.send(ControlRequest(command: command, busid: busid)) {
        guard response.ok else {
            throw CommandHandlerError.deviceBindingFailed(response.error ?? "the daemon refused the request")
        }
        return .daemon(changed: response.changed)
    }

    let changed: Bool
    switch command {
    case .bind:
        changed = try store.bind(busid)
    case .unbind:
        changed = try store.unbind(busid)
    }
    return .directly(changed: changed)
}

/// Bind command implementation
public class BindCommand: Command {
    public let name = "bind"
    public let description = "Make a USB device available over USB/IP"
    
    private let deviceDiscovery: DeviceDiscovery
    private let boundDevices: BoundDeviceStore
    private let ownershipInspector: DeviceOwnershipInspector

    public init(deviceDiscovery: DeviceDiscovery,
                boundDevices: BoundDeviceStore = BoundDeviceStore(),
                ownershipInspector: DeviceOwnershipInspector = DeviceOwnershipInspector()) {
        self.deviceDiscovery = deviceDiscovery
        self.boundDevices = boundDevices
        self.ownershipInspector = ownershipInspector
    }
    
    public func execute(with arguments: [String]) throws {
        logger.debug("Executing bind command", context: ["arguments": arguments.joined(separator: " ")])
        
        if arguments.isEmpty {
            logger.error("Missing required busid argument")
            throw CommandLineError.missingArguments("Device busid required")
        }
        
        if arguments.contains("-h") || arguments.contains("--help") {
            logger.debug("Showing help for bind command")
            printHelp()
            return
        }
        
        let busid = arguments[0]
        logger.debug("Processing bind request", context: ["busid": busid])
        
        // Validate busid format (e.g., 1-1, 2-3.4, etc.)
        let busidPattern = #"^\d+-\d+(\.\d+)*$"#
        guard busid.range(of: busidPattern, options: .regularExpression) != nil else {
            logger.error("Invalid busid format", context: ["busid": busid])
            throw CommandLineError.invalidArguments("Invalid busid format: \(busid)")
        }
        
        do {
            // Split busid into components (e.g., "1-2" -> busID: "1", deviceID: "2")
            let components = busid.split(separator: "-")
            guard components.count >= 2 else {
                logger.error("Invalid busid format after splitting", context: ["busid": busid])
                throw CommandLineError.invalidArguments("Invalid busid format: \(busid)")
            }
            
            let busPart = String(components[0])
            let devicePart = String(components[1])
            
            logger.debug("Looking for device", context: ["busID": busPart, "deviceID": devicePart])
            
            // Check if device exists
            guard let device = try deviceDiscovery.getDevice(busID: busPart, deviceID: devicePart) else {
                logger.error("Device not found", context: ["busid": busid])
                throw CommandHandlerError.deviceNotFound("No device found with busid \(busid)")
            }
            
            logger.info("Found device to bind", context: [
                "busID": device.busID,
                "deviceID": device.deviceID,
                "vendorID": String(format: "0x%04x", device.vendorID),
                "productID": String(format: "0x%04x", device.productID),
                "product": device.productString ?? "Unknown"
            ])
            
            let deviceIdentifier = "\(device.busID)-\(device.deviceID)"

            // Refuse devices something else already owns, before promising to share
            // them. This used to allow-list anything and only surface the problem when
            // a transfer failed, on a machine the user was no longer looking at.
            let ownership = ownershipInspector.ownership(vendorID: device.vendorID, productID: device.productID)
            switch ownership {
            case .unbound:
                break

            case .noInterfaces:
                // Nothing to open, so nothing can be served. Accepting the bind here
                // produced a device that looked shared and failed every transfer with
                // "Interface 0 not found".
                logger.info("Refusing to bind a device with no interfaces", context: ["busid": busid])
                print("Cannot share \(busid): the device exposes no USB interfaces.")
                print("macOS has not configured it, which usually means another process is")
                print("driving it directly — a browser tab using WebUSB, for instance. Quit")
                print("that program and try again.")
                throw CommandLineError.invalidArguments("Device \(busid) exposes no USB interfaces")

            case .partiallyClaimed(let free, let claimedBy):
                // Some interfaces are owned and some are not. A composite debug probe
                // looks like this: CMSIS-DAP free, the CDC serial port taken by macOS.
                // Refusing the whole device here rejected hardware that works.
                let names = claimedBy.joined(separator: ", ")
                let list = free.map(String.init).joined(separator: ", ")
                logger.info("Binding a partially claimed device", context: [
                    "busid": busid,
                    "freeInterfaces": list,
                    "claimedBy": names
                ])
                print("Note: macOS holds some interfaces of \(busid) (\(names)).")
                print("Interface \(list) is free and will be served — for a debug probe")
                print("that is the debug interface; the serial port stays with macOS.")

            case .kernelDriver(let drivers):
                let names = drivers.joined(separator: ", ")
                logger.error("Refusing to bind a driver-bound device", context: [
                    "busid": busid,
                    "drivers": names
                ])
                // Printed rather than folded into the thrown error: the error string is
                // also logged as context, and a multi-line message there is unreadable.
                print("""
                    Cannot share \(busid): macOS has bound a driver to it (\(names)).

                    Releasing it needs a DriverKit entitlement Apple has to grant.
                    Seizing the interface was measured and does not work, and neither
                    unmounting nor ejecting releases it.

                    Devices macOS does not claim — debug probes, boards in DFU mode,
                    vendor-specific interfaces — work today. Check a specific device
                    with ./Scripts/validate-usb-entitlements.sh
                    """)
                throw CommandHandlerError.deviceBindingFailed("\(busid) is owned by \(names)")

            case .userspaceProcess(let clients):
                let names = clients.joined(separator: ", ")
                logger.error("Refusing to bind a device held by another process", context: [
                    "busid": busid,
                    "clients": names
                ])
                print("""
                    Cannot share \(busid): another process has it open (\(names)).

                    Quit whatever is using the device — a camera or audio app, a
                    browser tab holding it over WebUSB — and bind again. Unlike a
                    kernel driver, this needs no entitlement.
                    """)
                throw CommandHandlerError.deviceBindingFailed("\(busid) is open in another process")
            }

            // Step 3: Record the device as bound.
            //
            // This writes only the bound-device list. It used to append to the server
            // configuration and write that whole file back, so sharing a USB device
            // rewrote the port, the log level and every tuning value along with it —
            // and reset them outright whenever the configuration had failed to parse.
            logger.debug("Recording the device as bound", context: ["deviceIdentifier": deviceIdentifier])
            let outcome = try applyBinding(.bind, busid: deviceIdentifier, store: boundDevices)
            if case .directly = outcome {
                print("Note: no daemon is running, so this was recorded for the next start.")
            }
            
            logger.info("Successfully bound device", context: ["busid": busid])
            print("✓ Device \(busid) added to server configuration")

            // Do not assert exclusive control. Nothing is claimed from macOS; bind
            // refuses driver-bound and process-held devices up front, so reaching here
            // means nothing else owns the interface.
            let identity = "\(busid): \(String(format: "%04x", device.vendorID)):\(String(format: "%04x", device.productID)) (\(device.productString ?? "Unknown"))"
            print("Bound device \(identity)")
            // Do not claim the whole device is free when only some of it is.
            if case .partiallyClaimed = ownership {
                print("Registered for USB/IP sharing. The free interface is served;")
                print("the interfaces macOS holds are not.")
            } else {
                print("Registered for USB/IP sharing. No driver or process holds this device.")
            }
        } catch let handlerError as CommandHandlerError {
            // Already carries its own message. Re-wrapping produced the doubled
            // "Device binding failed: Device binding failed: ..." prefix.
            throw handlerError
        } catch let deviceError as DeviceDiscoveryError {
            logger.error("Device discovery error during bind", context: ["error": deviceError.localizedDescription])
            throw CommandHandlerError.deviceBindingFailed(deviceError.localizedDescription)
        } catch let configError as ServerError {
            logger.error("Server configuration error during bind", context: ["error": configError.localizedDescription])
            throw CommandHandlerError.deviceBindingFailed(configError.localizedDescription)
        } catch {
            logger.error("Unexpected error during bind", context: ["error": error.localizedDescription])
            throw CommandHandlerError.deviceBindingFailed(error.localizedDescription)
        }
    }
    
    private func printHelp() {
        print("Usage: usbipd bind <busid>")
        print("")
        print("Bind a USB device for sharing through USB/IP. This command:")
        print("1. Refuses the device if macOS or another process holds its interfaces")
        print("2. Adds the device to the server's allowed device list")
        print("3. Prepares the device for remote USB/IP connections")
        print("")
        print("Arguments:")
        print("  busid           The bus ID of the USB device to bind (e.g., 1-1)")
        print("                  Use 'usbipd list' to see available devices")
        print("")
        print("Options:")
        print("  -h, --help      Show this help message")
        print("")
        print("Notes:")
        print("- Device will be unavailable to host system while bound")
        print("- Use 'usbipd unbind' to release the device")
    }
}

/// Unbind command implementation
public class UnbindCommand: Command {
    public let name = "unbind"
    public let description = "Stop making a USB device available over USB/IP"
    
    private let deviceDiscovery: DeviceDiscovery
    private let boundDevices: BoundDeviceStore
    
    public init(deviceDiscovery: DeviceDiscovery,
                boundDevices: BoundDeviceStore = BoundDeviceStore(),
                ) {
        self.deviceDiscovery = deviceDiscovery
        self.boundDevices = boundDevices
    }
    
    public func execute(with arguments: [String]) throws {
        logger.debug("Executing unbind command", context: ["arguments": arguments.joined(separator: " ")])
        
        if arguments.isEmpty {
            logger.error("Missing required busid argument")
            throw CommandLineError.missingArguments("Device busid required")
        }
        
        if arguments.contains("-h") || arguments.contains("--help") {
            logger.debug("Showing help for unbind command")
            printHelp()
            return
        }
        
        let busid = arguments[0]
        logger.debug("Processing unbind request", context: ["busid": busid])
        
        // Validate busid format
        let busidPattern = #"^\d+-\d+(\.\d+)*$"#
        guard busid.range(of: busidPattern, options: .regularExpression) != nil else {
            logger.error("Invalid busid format", context: ["busid": busid])
            throw CommandLineError.invalidArguments("Invalid busid format: \(busid)")
        }
        
        do {
            // Split busid into components for device lookup
            let components = busid.split(separator: "-")
            guard components.count >= 2 else {
                logger.error("Invalid busid format after splitting", context: ["busid": busid])
                throw CommandLineError.invalidArguments("Invalid busid format: \(busid)")
            }
            
            let busPart = String(components[0])
            let devicePart = String(components[1])
            
            logger.debug("Looking for device", context: ["busID": busPart, "deviceID": devicePart])
            
            logger.debug("Removing the device from the bound list", context: ["busid": busid])
            let unbindOutcome = try applyBinding(.unbind, busid: busid, store: boundDevices)
            let removed: Bool
            switch unbindOutcome {
            case .daemon(let changed):
                removed = changed
            case .directly(let changed):
                removed = changed
                if changed {
                    print("Note: no daemon is running; the change takes effect at the next start.")
                }
            }

            if removed {
                logger.info("Successfully unbound device", context: ["busid": busid])
                print("✓ Device \(busid) removed from server configuration")
                
                print("Device \(busid) successfully unbound from USB/IP sharing")
            } else {
                logger.info("Device was not bound", context: ["busid": busid])
                print("Device \(busid) was not bound")
            }
        } catch let deviceError as DeviceDiscoveryError {
            logger.error("Device discovery error during unbind", context: ["error": deviceError.localizedDescription])
            throw CommandHandlerError.deviceUnbindingFailed(deviceError.localizedDescription)
        } catch let configError as ServerError {
            logger.error("Server configuration error during unbind", context: ["error": configError.localizedDescription])
            throw CommandHandlerError.deviceUnbindingFailed(configError.localizedDescription)
        } catch {
            logger.error("Unexpected error during unbind", context: ["error": error.localizedDescription])
            throw CommandHandlerError.deviceUnbindingFailed(error.localizedDescription)
        }
    }
    
    private func printHelp() {
        print("Usage: usbipd unbind <busid>")
        print("")
        print("Unbind a USB device from USB/IP sharing. This command:")
        print("1. Releases exclusive access to the device through the System Extension")
        print("2. Removes the device from the server's allowed device list")
        print("3. Makes the device available to the host system again")
        print("")
        print("Arguments:")
        print("  busid           The bus ID of the USB device to unbind (e.g., 1-1)")
        print("                  Use 'usbipd list' to see available devices")
        print("")
        print("Options:")
        print("  -h, --help      Show this help message")
        print("")
        print("Notes:")
        print("- Handles both connected and disconnected devices gracefully")
        print("- Device will become available to host system after unbinding")
        print("- Use 'usbipd bind' to make the device shareable again")
    }
}

// AttachCommand and DetachCommand were removed. They are client-side operations —
// usbipd implements the server half of USB/IP — and both bodies did nothing but throw
// CommandHandlerError.operationNotSupported while still appearing in --help and in
// generated shell completions.

/// Whether a command actually started the server this process.
///
/// main.swift decides whether to block on RunLoop.main.run(). It used to decide by
/// looking for the word "daemon" in argv, which is not the same question:
/// `usbipd daemon --help` prints help, returns from execute(), and then had the
/// process block forever anyway. Ask the command what it did rather than guessing
/// from the arguments.
public enum DaemonRuntime {
    private static let lock = NSLock()
    private static var _serverDidStart = false

    public static var serverDidStart: Bool {
        lock.lock(); defer { lock.unlock() }
        return _serverDidStart
    }

    public static func markServerStarted() {
        lock.lock(); defer { lock.unlock() }
        _serverDidStart = true
    }
}

public class DaemonCommand: Command {
    public let name = "daemon"
    public let description = "Start USB/IP daemon"
    
    private let server: USBIPServer
    private let serverConfig: ServerConfig
    private let boundDevices: BoundDeviceStore

    /// Held for the daemon's lifetime; dropping it would close the socket.
    private var controlSocket: ControlSocketServer?

    public init(server: USBIPServer,
                serverConfig: ServerConfig,
                boundDevices: BoundDeviceStore = BoundDeviceStore()) {
        self.server = server
        self.serverConfig = serverConfig
        self.boundDevices = boundDevices
    }

    /// Serve bind and unbind requests from the CLI.
    ///
    /// Failing to open the socket is reported and then ignored. The daemon's job is
    /// serving USB devices, and it can still do that: `bind` falls back to writing the
    /// state file directly, which is how it worked before this existed.
    private func startControlSocket() {
        let socket = ControlSocketServer { [boundDevices] request in
            do {
                let changed: Bool
                switch request.command {
                case .bind:
                    changed = try boundDevices.bind(request.busid)
                case .unbind:
                    changed = try boundDevices.unbind(request.busid)
                }
                return ControlResponse(ok: true, changed: changed)
            } catch {
                return ControlResponse(ok: false, changed: false, error: error.localizedDescription)
            }
        }

        do {
            try socket.start()
            controlSocket = socket
        } catch {
            logger.warning("Control socket unavailable; bind will write the state file directly",
                           context: ["error": error.localizedDescription])
        }
    }
    
    public func execute(with arguments: [String]) throws {
        logger.debug("Executing daemon command", context: ["arguments": arguments.joined(separator: " ")])
        
        var foreground = false
        var configPath: String? = nil
        
        var i = 0
        while i < arguments.count {
            switch arguments[i] {
            case "-f", "--foreground":
                logger.debug("Running in foreground mode")
                foreground = true
                i += 1
            case "-c", "--config":
                if i + 1 < arguments.count {
                    configPath = arguments[i + 1]
                    logger.debug("Using custom config path", context: ["configPath": configPath!])
                    i += 2
                } else {
                    logger.error("Missing value for --config option")
                    throw CommandLineError.invalidArguments("Missing value for --config option")
                }
            case "-h", "--help":
                logger.debug("Showing help for daemon command")
                printHelp()
                return
            default:
                logger.error("Unknown option for daemon command", context: ["option": arguments[i]])
                throw CommandLineError.invalidArguments("Unknown option: \(arguments[i])")
            }
        }
        
        // Load configuration if specified
        if let configPath = configPath {
            logger.debug("Loading configuration from custom path", context: ["configPath": configPath])
            do {
                let loadedConfig = try ServerConfig.load(from: configPath)
                
                logger.info("Loaded custom configuration", context: [
                    "port": loadedConfig.port,
                    "logLevel": loadedConfig.logLevel.rawValue,
                    "debugMode": loadedConfig.debugMode ? "enabled" : "disabled"
                ])
                
                // Update the server's configuration
                // Note: This is a simplification; in a real implementation,
                // we would need to create a new server with the loaded config
                serverConfig.port = loadedConfig.port
                serverConfig.logLevel = loadedConfig.logLevel
                serverConfig.debugMode = loadedConfig.debugMode
                serverConfig.maxConnections = loadedConfig.maxConnections
                serverConfig.connectionTimeout = loadedConfig.connectionTimeout
                serverConfig.logFilePath = loadedConfig.logFilePath
                
                logger.debug("Applied custom configuration to server")
            } catch {
                logger.error("Failed to load configuration", context: ["error": error.localizedDescription])
                throw CommandHandlerError.serverStartFailed("Failed to load configuration: \(error.localizedDescription)")
            }
        }
        
        do {
            // Start the server
            logger.info("Starting USB/IP server", context: ["port": serverConfig.port])
            try server.start()
            DaemonRuntime.markServerStarted()
            startControlSocket()

            logger.info("USB/IP server started successfully", context: ["port": serverConfig.port])
            print("USB/IP daemon started on port \(serverConfig.port)")
            
            if foreground {
                logger.debug("Running in foreground mode")
                print("Running in foreground mode. Press Ctrl+C to stop.")
                
                // For the MVP, we'll just print a message and exit
                // In a real implementation, we would set up a proper signal handler
                // and keep the process running with RunLoop.main.run()
                print("Note: In the MVP, the server will run until the process is terminated.")
                print("In a full implementation, the server would handle signals properly.")
            } else {
                logger.debug("Running in background mode")
                print("Running in background mode.")
                // In a real implementation, we would daemonize the process here
                // For the MVP, we'll just exit and assume the server keeps running
            }
        } catch {
            logger.error("Failed to start server", context: ["error": error.localizedDescription])
            throw CommandHandlerError.serverStartFailed("Failed to start server: \(error.localizedDescription)")
        }
    }
    
    private func printHelp() {
        print("Usage: usbipd daemon [options]")
        print("")
        print("Options:")
        print("  -f, --foreground    Run in foreground (don't daemonize)")
        print("  -c, --config FILE   Use alternative configuration file")
        print("  -h, --help          Show this help message")
    }
}

// MARK: - Diagnostic Support Types

/// Diagnostic modes for targeted testing
private enum DiagnosticMode: String {
    case all
    case bundleDetection
    case installation
    case serviceManagement
}

/// Overall diagnostic status
private enum DiagnosticStatus: String, Comparable {
    case healthy
    case warning
    case critical
    
    static func < (lhs: DiagnosticStatus, rhs: DiagnosticStatus) -> Bool {
        let order: [DiagnosticStatus] = [.healthy, .warning, .critical]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
    
    static func max(_ lhs: DiagnosticStatus, _ rhs: DiagnosticStatus) -> DiagnosticStatus {
        return lhs > rhs ? lhs : rhs
    }
}

// OutputFormatter is now defined in OutputFormatter.swift

// MARK: - Concurrency Support

/// Thread-safe box for async-to-sync bridging
private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    
    init(_ value: T) {
        self._value = value
    }
    
    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}