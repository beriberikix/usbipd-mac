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
    public let description = "Bind a USB device to USB/IP through System Extension"
    
    private let deviceDiscovery: DeviceDiscovery
    private let serverConfig: ServerConfig
    private let systemExtensionManager: SystemExtensionManager?
    
    public init(deviceDiscovery: DeviceDiscovery, serverConfig: ServerConfig, systemExtensionManager: SystemExtensionManager? = nil) {
        self.deviceDiscovery = deviceDiscovery
        self.serverConfig = serverConfig
        self.systemExtensionManager = systemExtensionManager
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
            
            // Step 1: Validate System Extension is available and ready
            print("Checking System Extension status...")
            if let extensionManager = systemExtensionManager {
                logger.debug("System Extension Manager available for device claiming")
                
                // Check if device is already claimed
                if extensionManager.isDeviceClaimed(deviceID: deviceIdentifier) {
                    logger.info("Device already claimed by System Extension", context: ["deviceID": deviceIdentifier])
                    print("Device \(busid) is already claimed by System Extension")
                    
                    // Add to config even if already claimed to ensure consistency
                    serverConfig.allowDevice(deviceIdentifier)
                    try serverConfig.save()
                    
                    print("Device \(busid) successfully bound: \(String(format: "%04x", device.vendorID)):\(String(format: "%04x", device.productID)) (\(device.productString ?? "Unknown"))")
                    return
                }
                
                // Step 2: Attempt to claim device through System Extension
                print("Claiming device through System Extension...")
                logger.debug("Attempting device claim", context: ["deviceID": deviceIdentifier])
                
                do {
                    let claimedDevice = try extensionManager.claimDevice(device)
                    
                    logger.info("Successfully claimed device through System Extension", context: [
                        "deviceID": claimedDevice.deviceID,
                        "claimMethod": claimedDevice.claimMethod.rawValue,
                        "claimTime": claimedDevice.claimTime.timeIntervalSince1970
                    ])
                    print("✓ Device \(busid) successfully claimed by System Extension")
                    print("  Claim method: \(claimedDevice.claimMethod.rawValue)")
                    print("  Claimed at: \(DateFormatter.localizedString(from: claimedDevice.claimTime, dateStyle: .medium, timeStyle: .medium))")
                } catch {
                    logger.error("System Extension device claiming failed", context: [
                        "deviceID": deviceIdentifier,
                        "error": error.localizedDescription
                    ])
                    
                    let errorMsg = "System Extension failed to claim device \(busid): \(error.localizedDescription)"
                    print("✗ \(errorMsg)")
                    throw CommandHandlerError.deviceBindingFailed(errorMsg)
                }
            } else {
                logger.warning("System Extension Manager not available, using configuration-only binding")
                print("⚠ System Extension Manager not available - device will be bound in configuration only")
                print("Note: Device claiming through System Extension is not active")
            }
            
            // Step 3: Add device to allowed devices in config
            logger.debug("Adding device to allowed devices list", context: ["deviceIdentifier": deviceIdentifier])
            serverConfig.allowDevice(deviceIdentifier)
            
            // Step 4: Save the updated configuration
            logger.debug("Saving updated configuration")
            try serverConfig.save()
            
            logger.info("Successfully bound device", context: ["busid": busid])
            print("✓ Device \(busid) added to server configuration")
            print("Successfully bound device \(busid): \(String(format: "%04x", device.vendorID)):\(String(format: "%04x", device.productID)) (\(device.productString ?? "Unknown"))")
            
            if systemExtensionManager != nil {
                print("Device is now ready for USB/IP sharing with exclusive System Extension control")
            } else {
                print("Device is configured for USB/IP sharing (System Extension Manager not available)")
            }
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
        print("1. Claims exclusive access to the device through the System Extension")
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
        print("- Requires System Extension for exclusive device claiming")
        print("- Device will be unavailable to host system while bound")
        print("- Use 'usbipd unbind' to release the device")
    }
}

/// Unbind command implementation
public class UnbindCommand: Command {
    public let name = "unbind"
    public let description = "Unbind a USB device from USB/IP and release System Extension claim"
    
    private let deviceDiscovery: DeviceDiscovery
    private let serverConfig: ServerConfig
    private let systemExtensionManager: SystemExtensionManager?
    
    public init(deviceDiscovery: DeviceDiscovery, serverConfig: ServerConfig, systemExtensionManager: SystemExtensionManager? = nil) {
        self.deviceDiscovery = deviceDiscovery
        self.serverConfig = serverConfig
        self.systemExtensionManager = systemExtensionManager
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
            
            // Step 1: Check if device is currently bound in config
            let wasBound = serverConfig.allowedDevices.contains(busid)
            logger.debug("Device binding status in config", context: ["busid": busid, "wasBound": wasBound])
            
            // Step 2: Attempt to release device through System Extension if available
            if let extensionManager = systemExtensionManager {
                logger.debug("System Extension Manager available for device release")
                
                let deviceIdentifier = busid
                let isDeviceClaimed = extensionManager.isDeviceClaimed(deviceID: deviceIdentifier)
                
                if isDeviceClaimed {
                    print("Releasing device through System Extension...")
                    logger.debug("Attempting device release", context: ["deviceID": deviceIdentifier])
                    
                    do {
                        // Try to get the device info for release
                        if let device = try deviceDiscovery.getDevice(busID: busPart, deviceID: devicePart) {
                            try extensionManager.releaseDevice(device)
                            logger.info("Successfully released device through System Extension", context: ["deviceID": deviceIdentifier])
                            print("✓ Device \(busid) successfully released by System Extension")
                            print("  Device: \(String(format: "%04x", device.vendorID)):\(String(format: "%04x", device.productID)) (\(device.productString ?? "Unknown"))")
                            print("  Released at: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))")
                        } else {
                            // Device may have been disconnected - still try to release by identifier
                            logger.warning("Device not found during release, attempting cleanup", context: ["busid": busid])
                            print("⚠ Device \(busid) not found, but attempting System Extension cleanup...")
                            
                            // For disconnected devices, we still need to try to clean up the claim
                            // Create a minimal device object for cleanup
                            let cleanupDevice = USBDevice(
                                busID: busPart,
                                deviceID: devicePart,
                                vendorID: 0,
                                productID: 0,
                                deviceClass: 0,
                                deviceSubClass: 0,
                                deviceProtocol: 0,
                                speed: .unknown,
                                manufacturerString: nil,
                                productString: nil,
                                serialNumberString: nil
                            )
                            try extensionManager.releaseDevice(cleanupDevice)
                            logger.info("Successfully cleaned up disconnected device claim", context: ["deviceID": deviceIdentifier])
                            print("✓ Cleaned up System Extension claim for disconnected device \(busid)")
                        }
                    } catch {
                        logger.error("System Extension device release failed", context: [
                            "deviceID": deviceIdentifier,
                            "error": error.localizedDescription
                        ])
                        
                        let errorMsg = "System Extension failed to release device \(busid): \(error.localizedDescription)"
                        print("⚠ \(errorMsg)")
                        print("Note: Device will still be removed from server configuration")
                    }
                } else if wasBound {
                    logger.info("Device not claimed by System Extension but was bound in config", context: ["deviceID": deviceIdentifier])
                    print("Device \(busid) was not claimed by System Extension")
                } else {
                    logger.info("Device was not bound or claimed", context: ["busid": busid])
                }
            } else if wasBound {
                logger.warning("System Extension Manager not available for device release")
                print("⚠ System Extension Manager not available - releasing from configuration only")
                print("Note: Device claiming through System Extension is not active")
            }
            
            // Step 3: Remove device from allowed devices in config
            logger.debug("Removing device from allowed devices list", context: ["busid": busid])
            let removed = serverConfig.disallowDevice(busid)
            
            if removed {
                // Step 4: Save the updated configuration
                logger.debug("Saving updated configuration")
                try serverConfig.save()
                logger.info("Successfully unbound device from configuration", context: ["busid": busid])
                print("✓ Device \(busid) removed from server configuration")
                
                if systemExtensionManager != nil {
                    print("Device \(busid) successfully unbound and released from System Extension control")
                } else {
                    print("Device \(busid) successfully unbound from USB/IP sharing")
                }
            } else {
                if wasBound || systemExtensionManager?.isDeviceClaimed(deviceID: busid) == true {
                    logger.info("Device was claimed but not in config, still attempted release", context: ["busid": busid])
                    print("✓ Device \(busid) System Extension claim released (was not bound in configuration)")
                } else {
                    logger.info("Device was not bound or claimed", context: ["busid": busid])
                    print("Device \(busid) was not bound or claimed")
                }
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

/// System Extension installation command implementation
public class InstallSystemExtensionCommand: Command, InstallationProgressReporter {
    public let name = "install-system-extension"
    public let description = "Install and register the System Extension"
    
    private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "install-command")
    
    public init() {}
    
    public func execute(with arguments: [String]) throws {
        logger.debug("Executing install-system-extension command", context: ["arguments": arguments.joined(separator: " ")])
        
        // Parse options
        var verbose = false
        var skipVerification = false
        
        var i = 0
        while i < arguments.count {
            switch arguments[i] {
            case "-v", "--verbose":
                verbose = true
                i += 1
            case "--skip-verification":
                skipVerification = true
                i += 1
            case "-h", "--help":
                printHelp()
                return
            default:
                logger.error("Unknown option for install-system-extension command", context: ["option": arguments[i]])
                throw CommandLineError.invalidArguments("Unknown option: \(arguments[i])")
            }
        }
        
        logger.info("Starting System Extension installation", context: [
            "verbose": verbose,
            "skipVerification": skipVerification
        ])
        
        print("Starting System Extension installation...")
        print("This will register the System Extension with macOS and may require user approval.")
        print("")
        
        // Create installation orchestrator
        let orchestrator = InstallationOrchestrator()
        orchestrator.progressReporter = self
        
        // Run installation asynchronously
        let result = runAsyncInstallation(orchestrator: orchestrator)
        
        if result.success {
            logger.info("System Extension installation completed successfully")
            print("")
            print("✅ System Extension installation completed successfully!")
            
            if verbose {
                printVerboseResults(result: result)
            }
            
            if !result.recommendations.isEmpty {
                print("")
                print("Recommendations:")
                for recommendation in result.recommendations.prefix(5) {
                    print("  • \(recommendation)")
                }
            }
            
        } else {
            logger.error("System Extension installation failed", context: [
                "finalPhase": result.finalPhase.rawValue,
                "issues": result.issues.joined(separator: ", ")
            ])
            
            print("")
            print("❌ System Extension installation failed!")
            print("Final phase: \(result.finalPhase.rawValue)")
            
            if !result.issues.isEmpty {
                print("")
                print("Issues encountered:")
                for issue in result.issues {
                    print("  • \(issue)")
                }
            }
            
            if !result.recommendations.isEmpty {
                print("")
                print("Recommended actions:")
                for recommendation in result.recommendations.prefix(5) {
                    print("  • \(recommendation)")
                }
            }
            
            throw CommandHandlerError.operationNotSupported("System Extension installation failed")
        }
    }
    
    // MARK: - InstallationProgressReporter
    
    public func reportProgress(phase: OrchestrationPhase, progress: Double, message: String, userActions: [String]?) {
        let progressBar = createProgressBar(progress: progress)
        let phaseDescription = getPhaseDescription(phase: phase)
        
        print("\r\(progressBar) \(phaseDescription): \(message)", terminator: "")
        fflush(stdout)
        
        if let actions = userActions, !actions.isEmpty {
            print("")
            print("")
            print("User action required:")
            for action in actions {
                print("  → \(action)")
            }
            print("")
        }
        
        // Add newline for completed phases
        if progress >= 1.0 || phase == .completed || phase == .failed {
            print("")
        }
    }
    
    // MARK: - Private Implementation
    
    private func runAsyncInstallation(orchestrator: InstallationOrchestrator) -> OrchestrationResult {
        var installationResult: OrchestrationResult?
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            do {
                installationResult = await orchestrator.performCompleteInstallation()
            } catch {
                logger.error("Installation threw unexpected error", context: ["error": error.localizedDescription])
                installationResult = OrchestrationResult(
                    success: false,
                    finalPhase: .failed,
                    issues: ["Unexpected error: \(error.localizedDescription)"],
                    recommendations: ["Try running the installation again", "Check system logs for detailed error information"]
                )
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        return installationResult ?? OrchestrationResult(
            success: false,
            finalPhase: .failed,
            issues: ["Installation did not complete"],
            recommendations: ["Try running the installation again"]
        )
    }
    
    private func createProgressBar(progress: Double) -> String {
        let width = 20
        let completed = Int(progress * Double(width))
        let remaining = width - completed
        
        let completedBar = String(repeating: "█", count: completed)
        let remainingBar = String(repeating: "░", count: remaining)
        let percentage = String(format: "%3.0f", progress * 100)
        
        return "[\(completedBar)\(remainingBar)] \(percentage)%"
    }
    
    private func getPhaseDescription(phase: OrchestrationPhase) -> String {
        switch phase {
        case .bundleDetection:
            return "Bundle Detection"
        case .systemExtensionSubmission:
            return "System Registration"
        case .serviceIntegration:
            return "Service Integration"
        case .installationVerification:
            return "Verification"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }
    
    private func printVerboseResults(result: OrchestrationResult) {
        print("")
        print("Installation Details:")
        print("  Duration: \(String(format: "%.2f", result.duration)) seconds")
        print("  Final Phase: \(result.finalPhase.rawValue)")
        
        if let bundleResult = result.bundleDetectionResult {
            print("  Bundle Path: \(bundleResult.bundlePath ?? "unknown")")
            print("  Bundle ID: \(bundleResult.bundleIdentifier ?? "unknown")")
            print("  Environment: \(bundleResult.detectionEnvironment)")
        }
        
        if let submissionResult = result.submissionResult {
            print("  Submission Status: \(submissionResult.status)")
        }
        
        if let serviceResult = result.serviceIntegrationResult {
            print("  Service Integration: \(serviceResult.success ? "OK" : "Issues found")")
        }
        
        if let verificationResult = result.verificationResult {
            print("  Installation Status: \(verificationResult.status)")
        }
    }
    
    private func printHelp() {
        print("Usage: usbipd install-system-extension [options]")
        print("")
        print("Install and register the System Extension with macOS.")
        print("This may require user approval in System Preferences.")
        print("")
        print("Options:")
        print("  -v, --verbose           Show detailed installation information")
        print("  --skip-verification     Skip final installation verification")
        print("  -h, --help              Show this help message")
    }
}

// OutputFormatter is now defined in OutputFormatter.swift