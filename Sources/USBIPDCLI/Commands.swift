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
        print("Version: 0.1.0")
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
                logger.info("No USB devices found")
                print("No USB devices found.")
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

/// Bind command implementation
public class BindCommand: Command {
    public let name = "bind"
    public let description = "Bind a USB device to USB/IP"
    
    private let deviceDiscovery: DeviceDiscovery
    private let serverConfig: ServerConfig
    
    public init(deviceDiscovery: DeviceDiscovery, serverConfig: ServerConfig) {
        self.deviceDiscovery = deviceDiscovery
        self.serverConfig = serverConfig
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
            
            // Add device to allowed devices in config
            let deviceIdentifier = "\(device.busID)-\(device.deviceID)"
            serverConfig.allowDevice(deviceIdentifier)
            
            logger.debug("Added device to allowed devices list", context: ["deviceIdentifier": deviceIdentifier])
            
            // Save the updated configuration
            logger.debug("Saving updated configuration")
            try serverConfig.save()
            
            logger.info("Successfully bound device", context: ["busid": busid])
            print("Successfully bound device \(busid): \(device.vendorID.hexString):\(device.productID.hexString) (\(device.productString ?? "Unknown"))")
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
        print("Arguments:")
        print("  busid           The bus ID of the USB device to bind (e.g., 1-1)")
        print("")
        print("Options:")
        print("  -h, --help      Show this help message")
    }
}

/// Unbind command implementation
public class UnbindCommand: Command {
    public let name = "unbind"
    public let description = "Unbind a USB device from USB/IP"
    
    private let deviceDiscovery: DeviceDiscovery
    private let serverConfig: ServerConfig
    
    public init(deviceDiscovery: DeviceDiscovery, serverConfig: ServerConfig) {
        self.deviceDiscovery = deviceDiscovery
        self.serverConfig = serverConfig
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
            // Remove device from allowed devices in config
            logger.debug("Removing device from allowed devices list", context: ["busid": busid])
            let removed = serverConfig.disallowDevice(busid)
            
            if removed {
                // Save the updated configuration
                logger.debug("Saving updated configuration")
                try serverConfig.save()
                logger.info("Successfully unbound device", context: ["busid": busid])
                print("Successfully unbound device \(busid)")
            } else {
                logger.info("Device was not bound", context: ["busid": busid])
                print("Device \(busid) was not bound")
            }
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
        print("Arguments:")
        print("  busid           The bus ID of the USB device to unbind (e.g., 1-1)")
        print("")
        print("Options:")
        print("  -h, --help      Show this help message")
    }
}

/// Attach command implementation
public class AttachCommand: Command {
    public let name = "attach"
    public let description = "Attach a remote USB device"
    
    public func execute(with arguments: [String]) throws {
        if arguments.count < 2 {
            throw CommandLineError.missingArguments("Remote host and busid required")
        }
        
        if arguments.contains("-h") || arguments.contains("--help") {
            printHelp()
            return
        }
        
        // We don't need to use these values since we're not implementing this functionality yet
        _ = arguments[0] // host
        _ = arguments[1] // busid
        
        // For MVP, this is a placeholder as we don't implement client functionality yet
        throw CommandHandlerError.operationNotSupported("The attach command is not supported in this version. This server implementation does not include client functionality.")
    }
    
    private func printHelp() {
        print("Usage: usbipd attach <host> <busid>")
        print("")
        print("Arguments:")
        print("  host            The remote host running USB/IP server")
        print("  busid           The bus ID of the USB device to attach (e.g., 1-1)")
        print("")
        print("Options:")
        print("  -h, --help      Show this help message")
    }
}

/// Detach command implementation
public class DetachCommand: Command {
    public let name = "detach"
    public let description = "Detach a remote USB device"
    
    public func execute(with arguments: [String]) throws {
        if arguments.isEmpty {
            throw CommandLineError.missingArguments("Port number required")
        }
        
        if arguments.contains("-h") || arguments.contains("--help") {
            printHelp()
            return
        }
        
        // Validate port is a number, but we don't need to use it
        guard Int(arguments[0]) != nil else {
            throw CommandLineError.invalidArguments("Port must be a number")
        }
        
        // For MVP, this is a placeholder as we don't implement client functionality yet
        throw CommandHandlerError.operationNotSupported("The detach command is not supported in this version. This server implementation does not include client functionality.")
    }
    
    private func printHelp() {
        print("Usage: usbipd detach <port>")
        print("")
        print("Arguments:")
        print("  port            The port number of the attached device")
        print("")
        print("Options:")
        print("  -h, --help      Show this help message")
    }
}

/// Daemon command implementation
public class DaemonCommand: Command {
    public let name = "daemon"
    public let description = "Start USB/IP daemon"
    
    private let server: USBIPServer
    private let serverConfig: ServerConfig
    
    public init(server: USBIPServer, serverConfig: ServerConfig) {
        self.server = server
        self.serverConfig = serverConfig
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
                serverConfig.allowedDevices = loadedConfig.allowedDevices
                serverConfig.autoBindDevices = loadedConfig.autoBindDevices
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

// OutputFormatter is now defined in OutputFormatter.swift