// Commands.swift
// Implementation of CLI commands for USB/IP daemon

import Foundation
import USBIPDCore
import Common

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
        print("USB/IP Daemon for macOS")
        print("Version: 0.1.0")
        print("")
        print("Usage: usbipd [command] [options]")
        print("")
        print("Commands:")
        
        guard let commands = parser?.getCommands() else {
            return
        }
        
        // Sort commands alphabetically for consistent display
        let sortedCommands = commands.sorted { $0.name < $1.name }
        
        for command in sortedCommands {
            print("  \(command.name.padding(toLength: 10, withPad: " ", startingAt: 0)) \(command.description)")
        }
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
        // Parse options
        var showRemoteOnly = false
        
        for arg in arguments {
            switch arg {
            case "-l", "--local":
                // Local is the default, so we don't need to do anything
                break
            case "-r", "--remote":
                showRemoteOnly = true
            case "-h", "--help":
                printHelp()
                return
            default:
                throw CommandLineError.invalidArguments("Unknown option: \(arg)")
            }
        }
        
        // For MVP, we only support local devices
        if showRemoteOnly {
            print("Remote device listing is not supported in this version")
            return
        }
        
        do {
            // Get devices from device discovery
            let devices = try deviceDiscovery.discoverDevices()
            
            // Format and print the device list
            let formattedOutput = outputFormatter.formatDeviceList(devices)
            print(formattedOutput)
            
            if devices.isEmpty {
                print("No USB devices found.")
            }
        } catch {
            // Log the error and rethrow
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
        if arguments.isEmpty {
            throw CommandLineError.missingArguments("Device busid required")
        }
        
        if arguments.contains("-h") || arguments.contains("--help") {
            printHelp()
            return
        }
        
        let busid = arguments[0]
        
        // Validate busid format (e.g., 1-1, 2-3.4, etc.)
        let busidPattern = #"^\d+-\d+(\.\d+)*$"#
        guard busid.range(of: busidPattern, options: .regularExpression) != nil else {
            throw CommandLineError.invalidArguments("Invalid busid format: \(busid)")
        }
        
        do {
            // Split busid into components (e.g., "1-2" -> busID: "1", deviceID: "2")
            let components = busid.split(separator: "-")
            guard components.count >= 2 else {
                throw CommandLineError.invalidArguments("Invalid busid format: \(busid)")
            }
            
            let busPart = String(components[0])
            let devicePart = String(components[1])
            
            // Check if device exists
            guard let device = try deviceDiscovery.getDevice(busID: busPart, deviceID: devicePart) else {
                throw CommandHandlerError.deviceNotFound("No device found with busid \(busid)")
            }
            
            // Add device to allowed devices in config
            let deviceIdentifier = "\(device.busID)-\(device.deviceID)"
            serverConfig.allowDevice(deviceIdentifier)
            
            // Save the updated configuration
            try serverConfig.save()
            
            print("Successfully bound device \(busid): \(device.vendorID.hexString):\(device.productID.hexString) (\(device.productString ?? "Unknown"))")
        } catch let deviceError as DeviceDiscoveryError {
            throw CommandHandlerError.deviceBindingFailed(deviceError.localizedDescription)
        } catch let configError as ServerError {
            throw CommandHandlerError.deviceBindingFailed(configError.localizedDescription)
        } catch {
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
        if arguments.isEmpty {
            throw CommandLineError.missingArguments("Device busid required")
        }
        
        if arguments.contains("-h") || arguments.contains("--help") {
            printHelp()
            return
        }
        
        let busid = arguments[0]
        
        // Validate busid format
        let busidPattern = #"^\d+-\d+(\.\d+)*$"#
        guard busid.range(of: busidPattern, options: .regularExpression) != nil else {
            throw CommandLineError.invalidArguments("Invalid busid format: \(busid)")
        }
        
        do {
            // Remove device from allowed devices in config
            let removed = serverConfig.disallowDevice(busid)
            
            if removed {
                // Save the updated configuration
                try serverConfig.save()
                print("Successfully unbound device \(busid)")
            } else {
                print("Device \(busid) was not bound")
            }
        } catch let configError as ServerError {
            throw CommandHandlerError.deviceUnbindingFailed(configError.localizedDescription)
        } catch {
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
        var foreground = false
        var configPath: String? = nil
        
        var i = 0
        while i < arguments.count {
            switch arguments[i] {
            case "-f", "--foreground":
                foreground = true
                i += 1
            case "-c", "--config":
                if i + 1 < arguments.count {
                    configPath = arguments[i + 1]
                    i += 2
                } else {
                    throw CommandLineError.invalidArguments("Missing value for --config option")
                }
            case "-h", "--help":
                printHelp()
                return
            default:
                throw CommandLineError.invalidArguments("Unknown option: \(arguments[i])")
            }
        }
        
        // Load configuration if specified
        if let configPath = configPath {
            do {
                let loadedConfig = try ServerConfig.load(from: configPath)
                
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
            } catch {
                throw CommandHandlerError.serverStartFailed("Failed to load configuration: \(error.localizedDescription)")
            }
        }
        
        do {
            // Start the server
            try server.start()
            
            print("USB/IP daemon started on port \(serverConfig.port)")
            
            if foreground {
                print("Running in foreground mode. Press Ctrl+C to stop.")
                
                // For the MVP, we'll just print a message and exit
                // In a real implementation, we would set up a proper signal handler
                // and keep the process running with RunLoop.main.run()
                print("Note: In the MVP, the server will run until the process is terminated.")
                print("In a full implementation, the server would handle signals properly.")
            } else {
                print("Running in background mode.")
                // In a real implementation, we would daemonize the process here
                // For the MVP, we'll just exit and assume the server keeps running
            }
        } catch {
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