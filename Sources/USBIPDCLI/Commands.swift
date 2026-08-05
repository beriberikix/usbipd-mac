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
                logger.warning("System Extension Manager not available; device allow-listed without an exclusive claim")
                print("⚠ System Extension is not active - this device was added to the allow-list only.")
                print("  No exclusive claim was taken. Devices macOS has already bound to a kernel")
                print("  driver (USB-serial, HID, mass storage) will NOT be servable in this state.")
                print("  Devices with no kernel driver bound - debug probes, DFU/bootloader modes -")
                print("  work from userspace and need no claim.")
            }
            
            // Step 3: Add device to allowed devices in config
            logger.debug("Adding device to allowed devices list", context: ["deviceIdentifier": deviceIdentifier])
            serverConfig.allowDevice(deviceIdentifier)
            
            // Step 4: Save the updated configuration
            logger.debug("Saving updated configuration")
            try serverConfig.save()
            
            logger.info("Successfully bound device", context: ["busid": busid])
            print("✓ Device \(busid) added to server configuration")

            // Report what actually happened. This previously printed "Successfully
            // bound" for both outcomes, so a run that took no exclusive claim at all
            // was indistinguishable from one that did.
            let identity = "\(busid): \(String(format: "%04x", device.vendorID)):\(String(format: "%04x", device.productID)) (\(device.productString ?? "Unknown"))"
            if systemExtensionManager != nil {
                print("Successfully bound device \(identity)")
                print("Device is claimed and ready for USB/IP sharing with exclusive System Extension control")
            } else {
                print("Allow-listed device \(identity)")
                print("Not claimed: the System Extension is not active. See the warning above.")
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

// AttachCommand and DetachCommand were removed. They are client-side operations —
// usbipd implements the server half of USB/IP — and both bodies did nothing but throw
// CommandHandlerError.operationNotSupported while still appearing in --help and in
// generated shell completions.

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
        // Use semaphore-based async-to-sync bridging for proper concurrency compliance
        let resultBox = Box<OrchestrationResult?>(nil)
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            let result = await orchestrator.performCompleteInstallation()
            resultBox.value = result
            semaphore.signal()
        }
        
        semaphore.wait()
        
        return resultBox.value ?? OrchestrationResult(
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

/// Comprehensive diagnostic command implementation
public class DiagnoseCommand: Command {
    public let name = "diagnose"
    public let description = "Run comprehensive installation and system diagnostics"
    
    private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "diagnose-command")
    
    public init() {}
    
    public func execute(with arguments: [String]) throws {
        logger.debug("Executing diagnose command", context: ["arguments": arguments.joined(separator: " ")])
        
        // Parse options
        var verbose = false
        var mode: DiagnosticMode = .all
        
        var i = 0
        while i < arguments.count {
            switch arguments[i] {
            case "-v", "--verbose":
                verbose = true
                i += 1
            case "--bundle":
                mode = .bundleDetection
                i += 1
            case "--installation":
                mode = .installation
                i += 1
            case "--service":
                mode = .serviceManagement
                i += 1
            case "--all":
                mode = .all
                i += 1
            case "-h", "--help":
                printHelp()
                return
            default:
                logger.error("Unknown option for diagnose command", context: ["option": arguments[i]])
                throw CommandLineError.invalidArguments("Unknown option: \(arguments[i])")
            }
        }
        
        logger.info("Starting diagnostic scan", context: [
            "verbose": verbose,
            "mode": mode.rawValue
        ])
        
        print("🔍 USB/IP System Extension Diagnostics")
        print("=====================================")
        print("")
        
        // Track overall diagnostic status
        var overallStatus = DiagnosticStatus.healthy
        var issueCount = 0
        var warningCount = 0
        
        // Run bundle detection diagnostics
        if mode == .all || mode == .bundleDetection {
            print("📦 Bundle Detection Diagnostics")
            print("-------------------------------")
            let bundleStatus = runBundleDetectionDiagnostics(verbose: verbose)
            updateOverallStatus(&overallStatus, with: bundleStatus, &issueCount, &warningCount)
            print("")
        }
        
        // Run installation diagnostics
        if mode == .all || mode == .installation {
            print("⚙️  Installation Diagnostics")
            print("----------------------------")
            let installationStatus = runInstallationDiagnostics(verbose: verbose)
            updateOverallStatus(&overallStatus, with: installationStatus, &issueCount, &warningCount)
            print("")
        }
        
        // Run service management diagnostics
        if mode == .all || mode == .serviceManagement {
            print("🔧 Service Management Diagnostics")
            print("---------------------------------")
            let serviceStatus = runServiceManagementDiagnostics(verbose: verbose)
            updateOverallStatus(&overallStatus, with: serviceStatus, &issueCount, &warningCount)
            print("")
        }
        
        // Print overall summary
        printOverallSummary(status: overallStatus, issueCount: issueCount, warningCount: warningCount)
        
        logger.info("Diagnostic scan completed", context: [
            "overallStatus": overallStatus.rawValue,
            "issueCount": issueCount,
            "warningCount": warningCount
        ])
    }
    
    // MARK: - Bundle Detection Diagnostics
    
    private func runBundleDetectionDiagnostics(verbose: Bool) -> DiagnosticStatus {
        var status = DiagnosticStatus.healthy
        
        // Test bundle detector
        let bundleDetector = SystemExtensionBundleDetector()
        let detectionResult = bundleDetector.detectBundle()
        
        if detectionResult.found {
            print("✅ System Extension bundle detected")
            if verbose {
                print("   📁 Path: \(detectionResult.bundlePath ?? "unknown")")
                print("   🆔 Bundle ID: \(detectionResult.bundleIdentifier ?? "unknown")")
                print("   🏠 Environment: \(formatDetectionEnvironment(detectionResult.detectionEnvironment))")
                print("   🕐 Detection Time: \(DateFormatter.localizedString(from: detectionResult.detectionTime, dateStyle: .medium, timeStyle: .short))")
                
                if let metadata = detectionResult.homebrewMetadata {
                    print("   📦 Homebrew Version: \(metadata.version ?? "unknown")")
                    if let installDate = metadata.installationDate {
                        print("   📅 Installation Date: \(DateFormatter.localizedString(from: installDate, dateStyle: .medium, timeStyle: .short))")
                    }
                }
                
                // Show enhanced diagnostic information
                if !detectionResult.skippedPaths.isEmpty {
                    print("   ⏭️  Skipped Paths (\(detectionResult.skippedPaths.count)):")
                    let pathsToShow = Array(detectionResult.skippedPaths.prefix(5))
                    for skippedPath in pathsToShow {
                        let reason = detectionResult.rejectionReasons[skippedPath]
                        let reasonText = formatRejectionReason(reason)
                        print("      • \(skippedPath) (\(reasonText))")
                    }
                    if detectionResult.skippedPaths.count > 5 {
                        print("      ... and \(detectionResult.skippedPaths.count - 5) more paths")
                    }
                }
            }
        } else {
            print("❌ System Extension bundle NOT detected")
            
            // Provide enhanced diagnostic information for troubleshooting
            if !detectionResult.issues.isEmpty {
                print("   Issues encountered:")
                for issue in detectionResult.issues.prefix(verbose ? 10 : 3) {
                    print("      • \(issue)")
                }
                if !verbose && detectionResult.issues.count > 3 {
                    print("      ... and \(detectionResult.issues.count - 3) more issues (use --verbose to see all)")
                }
            }
            
            if !detectionResult.skippedPaths.isEmpty && verbose {
                print("   Searched paths (\(detectionResult.skippedPaths.count)):")
                for skippedPath in detectionResult.skippedPaths.prefix(5) {
                    let reason = detectionResult.rejectionReasons[skippedPath]
                    let reasonText = formatRejectionReason(reason)
                    print("      • \(skippedPath) (\(reasonText))")
                }
                if detectionResult.skippedPaths.count > 5 {
                    print("      ... and \(detectionResult.skippedPaths.count - 5) more paths")
                }
            }
            
            // Provide specific recommendations based on detection environment
            switch detectionResult.detectionEnvironment {
            case .development:
                print("   💡 Recommendations:")
                print("      • Run 'swift build' to build the System Extension")
                print("      • Ensure you're in the project root directory")
            case .homebrew:
                print("   💡 Recommendations:")
                print("      • Install usbipd-mac via Homebrew: brew install usbip")
                print("      • If already installed, try: brew reinstall usbip")
            case .manual, .unknown:
                print("   💡 Recommendations:")
                print("      • Install usbipd-mac via Homebrew: brew install usbip")
                print("      • Or run 'swift build' if in development environment")
            }
            
            status = .critical
        }
        
        // Test bundle validation
        if detectionResult.found, let bundlePath = detectionResult.bundlePath {
            let bundleValidation = validateBundleStructure(bundlePath: bundlePath, verbose: verbose)
            if bundleValidation != .healthy {
                status = max(status, bundleValidation)
            }
        }
        
        return status
    }
    
    private func validateBundleStructure(bundlePath: String, verbose: Bool) -> DiagnosticStatus {
        let requiredFiles = [
            "Contents/Info.plist",
            "Contents/MacOS/USBIPDSystemExtension"
        ]
        
        var missingFiles: [String] = []
        
        for file in requiredFiles {
            let fullPath = "\(bundlePath)/\(file)"
            if !FileManager.default.fileExists(atPath: fullPath) {
                missingFiles.append(file)
            }
        }
        
        if missingFiles.isEmpty {
            print("✅ Bundle structure is valid")
            if verbose {
                print("   📋 All required files present")
                for file in requiredFiles {
                    print("      • \(file)")
                }
            }
            return .healthy
        } else {
            print("⚠️  Bundle structure issues detected")
            print("   Missing files:")
            for file in missingFiles {
                print("      • \(file)")
            }
            print("   💡 Reinstall usbipd-mac: brew reinstall usbip")
            return .warning
        }
    }
    
    // MARK: - Installation Diagnostics
    
    private func runInstallationDiagnostics(verbose: Bool) -> DiagnosticStatus {
        var status = DiagnosticStatus.healthy
        
        // Run installation verification using the enhanced verification manager
        let verificationManager = InstallationVerificationManager()
        
        // Create a blocking wrapper for the async verification using semaphore with timeout
        let resultBox = Box<InstallationVerificationResult?>(nil)
        let completionBox = Box<Bool>(false)
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            let verificationResult = await verificationManager.verifyInstallation()
            resultBox.value = verificationResult
            completionBox.value = true
            semaphore.signal()
        }
        
        // Wait with timeout (30 seconds)
        let result = semaphore.wait(timeout: .now() + 30.0)
        
        if result == .timedOut {
            print("⏱️ Installation verification timed out after 30 seconds")
            return .warning
        }
        
        guard let result = resultBox.value else {
            print("❌ Installation verification failed to run")
            return .critical
        }
        
        // Report installation status
        switch result.status {
        case .fullyFunctional:
            print("✅ System Extension is fully functional")
        case .partiallyFunctional:
            print("⚠️  System Extension is partially functional")
            status = .warning
        case .problematic:
            print("⚠️  System Extension has problems")
            status = .warning
        case .failed:
            print("❌ System Extension installation failed")
            status = .critical
        case .unknown:
            print("❓ System Extension status unknown")
            status = .warning
        }
        
        if verbose {
            print("   📊 Verification checks completed: \(result.verificationChecks.count)")
            print("   ✅ Checks passed: \(result.verificationChecks.filter { $0.passed }.count)")
            print("   ⚠️  Issues found: \(result.discoveredIssues.count)")
        }
        
        // Report discovered issues
        if !result.discoveredIssues.isEmpty {
            print("   Issues discovered:")
            for issue in result.discoveredIssues.prefix(verbose ? 10 : 3) {
                print("      • \(issue.description)")
                if verbose, let remediation = issue.remediation {
                    print("        💡 \(remediation)")
                }
            }
            
            if !verbose && result.discoveredIssues.count > 3 {
                print("      ... and \(result.discoveredIssues.count - 3) more (use --verbose to see all)")
            }
        }
        
        // Test systemextensionsctl integration
        if verbose {
            print("   🔍 Testing systemextensionsctl integration...")
            testSystemExtensionsCtlIntegration()
        }
        
        return status
    }
    
    func testSystemExtensionsCtlIntegration() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
        task.arguments = ["list"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                print("      ✅ systemextensionsctl is accessible")
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                if output.contains("com.github.usbipd-mac.systemextension") {
                    print("      ✅ USB/IP System Extension found in registry")
                } else {
                    print("      ⚠️  USB/IP System Extension not found in registry")
                }
            } else {
                print("      ❌ systemextensionsctl command failed")
            }
        } catch {
            print("      ❌ Failed to execute systemextensionsctl: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Service Management Diagnostics
    
    private func runServiceManagementDiagnostics(verbose: Bool) -> DiagnosticStatus {
        var status = DiagnosticStatus.healthy
        
        // Test service lifecycle manager
        let serviceManager = ServiceLifecycleManager()
        
        // Run service status detection
        let serviceStatusTask = Task {
            return await serviceManager.detectServiceStatus()
        }
        
        // Wait for the async task to complete (simplified for CLI)
        _ = Task {
            await serviceStatusTask.value
        }
        
        // For MVP, we'll create a basic implementation
        print("🔍 Checking service management status...")
        
        // Check brew services status
        let brewStatus = checkBrewServicesStatus(verbose: verbose)
        if brewStatus != .healthy {
            status = max(status, brewStatus)
        }
        
        // Check launchd integration
        let launchdStatus = checkLaunchdIntegration(verbose: verbose)
        if launchdStatus != .healthy {
            status = max(status, launchdStatus)
        }
        
        // Check for conflicting processes
        let conflictStatus = checkForConflictingProcesses(verbose: verbose)
        if conflictStatus != .healthy {
            status = max(status, conflictStatus)
        }
        
        return status
    }
    
    private func checkBrewServicesStatus(verbose: Bool) -> DiagnosticStatus {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["brew", "services", "list"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                if output.contains("usbipd-mac") {
                    let lines = output.components(separatedBy: .newlines)
                    if let usbipLine = lines.first(where: { $0.contains("usbipd-mac") }) {
                        if usbipLine.contains("started") {
                            print("✅ Homebrew service is running")
                            if verbose {
                                print("   📋 Status: \(usbipLine.trimmingCharacters(in: .whitespaces))")
                            }
                        } else if usbipLine.contains("stopped") {
                            print("ℹ️  Homebrew service is stopped (normal when not in use)")
                            if verbose {
                                print("   📋 Status: \(usbipLine.trimmingCharacters(in: .whitespaces))")
                            }
                        } else {
                            print("⚠️  Homebrew service status unclear")
                            if verbose {
                                print("   📋 Status: \(usbipLine.trimmingCharacters(in: .whitespaces))")
                            }
                            return .warning
                        }
                    }
                } else {
                    print("ℹ️  Homebrew service not found (not started)")
                }
                return .healthy
            } else {
                print("⚠️  Could not check Homebrew services status")
                return .warning
            }
        } catch {
            print("❌ Failed to check Homebrew services: \(error.localizedDescription)")
            return .critical
        }
    }
    
    private func checkLaunchdIntegration(verbose: Bool) -> DiagnosticStatus {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["list"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                print("✅ launchctl is accessible")
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                if output.contains("usbipd") {
                    print("ℹ️  usbipd-related services found in launchd")
                    if verbose {
                        let lines = output.components(separatedBy: .newlines)
                        let usbipLines = lines.filter { $0.contains("usbipd") }
                        for line in usbipLines.prefix(3) {
                            print("   📋 \(line.trimmingCharacters(in: .whitespaces))")
                        }
                    }
                } else {
                    print("ℹ️  No usbipd services currently registered with launchd")
                }
                return .healthy
            } else {
                print("⚠️  launchctl command failed")
                return .warning
            }
        } catch {
            print("❌ Failed to check launchd: \(error.localizedDescription)")
            return .critical
        }
    }
    
    private func checkForConflictingProcesses(verbose: Bool) -> DiagnosticStatus {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["aux"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                let usbipProcesses = output.components(separatedBy: .newlines)
                    .filter { $0.contains("usbipd") || $0.contains("USBIPDSystemExtension") }
                    .filter { !$0.contains("ps aux") } // Exclude the ps command itself
                
                if usbipProcesses.isEmpty {
                    print("ℹ️  No usbipd processes currently running")
                } else {
                    print("ℹ️  Found \(usbipProcesses.count) usbipd-related process(es)")
                    if verbose {
                        for process in usbipProcesses.prefix(5) {
                            let components = process.components(separatedBy: .whitespaces)
                            if components.count >= 11 {
                                let pid = components[1]
                                let command = components[10...]
                                print("   📋 PID \(pid): \(command.joined(separator: " "))")
                            }
                        }
                    }
                }
                return .healthy
            } else {
                print("⚠️  Could not check for running processes")
                return .warning
            }
        } catch {
            print("❌ Failed to check for conflicting processes: \(error.localizedDescription)")
            return .critical
        }
    }
    
    // MARK: - Diagnostic Formatting Utilities
    
    private func formatDetectionEnvironment(_ environment: SystemExtensionBundleDetector.DetectionEnvironment) -> String {
        switch environment {
        case .development(let buildPath):
            return "Development (\(buildPath))"
        case .homebrew(let cellarPath, let version):
            if let version = version {
                return "Homebrew (\(version))"
            } else {
                return "Homebrew (\(cellarPath))"
            }
        case .manual(let bundlePath):
            return "Manual (\(bundlePath))"
        case .unknown:
            return "Unknown"
        }
    }
    
    private func formatRejectionReason(_ reason: SystemExtensionBundleDetector.RejectionReason?) -> String {
        guard let reason = reason else { return "Unknown" }
        
        switch reason {
        case .dSYMPath:
            return "dSYM directory"
        case .missingExecutable:
            return "missing executable"
        case .invalidBundleStructure:
            return "invalid bundle structure"
        case .missingInfoPlist:
            return "missing Info.plist"
        }
    }
    
    // MARK: - Summary and Utilities
    
    private func updateOverallStatus(_ overallStatus: inout DiagnosticStatus, with sectionStatus: DiagnosticStatus, _ issueCount: inout Int, _ warningCount: inout Int) {
        switch sectionStatus {
        case .critical:
            issueCount += 1
            overallStatus = .critical
        case .warning:
            warningCount += 1
            if overallStatus != .critical {
                overallStatus = .warning
            }
        case .healthy:
            break
        }
    }
    
    private func printOverallSummary(status: DiagnosticStatus, issueCount: Int, warningCount: Int) {
        print("🏁 Overall Diagnostic Summary")
        print("============================")
        
        switch status {
        case .healthy:
            print("✅ System is healthy")
            print("   All diagnostic checks passed successfully.")
        case .warning:
            print("⚠️  System has warnings")
            print("   \(warningCount) warning(s) found. System should function but may have issues.")
        case .critical:
            print("❌ System has critical issues")
            print("   \(issueCount) critical issue(s) found. System may not function properly.")
        }
        
        print("")
        print("💡 Recommendations:")
        
        switch status {
        case .healthy:
            print("   • System is ready for use")
            print("   • Run 'usbipd list' to see available devices")
            print("   • Use 'usbipd bind <busid>' to share devices")
        case .warning:
            print("   • Review warnings above and address if possible")
            print("   • Try restarting the System Extension: 'sudo systemextensionsctl reset'")
            print("   • System may still function with current warnings")
        case .critical:
            print("   • Address critical issues before using the system")
            print("   • If no System Extension bundle found:")
            print("     - Development: Run 'swift build' in project directory")
            print("     - Production: Install via 'brew install usbip'")
            print("   • If bundle found but installation failed:")
            print("     - Run installation: 'usbipd install-system-extension'")
            print("     - Check System Preferences > Security & Privacy for approvals")
            print("   • If persistent issues: 'brew reinstall usbip'")
        }
    }
    
    private func printHelp() {
        print("Usage: usbipd diagnose [options]")
        print("")
        print("Run comprehensive system diagnostics to identify issues with")
        print("System Extension installation, bundle detection, and service management.")
        print("")
        print("Options:")
        print("  -v, --verbose           Show detailed diagnostic information")
        print("  --bundle                Run only bundle detection diagnostics")
        print("  --installation          Run only installation status diagnostics")
        print("  --service               Run only service management diagnostics")
        print("  --all                   Run all diagnostic modes (default)")
        print("  -h, --help              Show this help message")
        print("")
        print("Diagnostic Modes:")
        print("  Bundle Detection        Checks System Extension bundle presence and validity")
        print("  Installation            Verifies System Extension registration with macOS")
        print("  Service Management      Checks Homebrew services and launchd integration")
        print("")
        print("Examples:")
        print("  usbipd diagnose                    # Run all diagnostics")
        print("  usbipd diagnose --verbose          # Detailed output")
        print("  usbipd diagnose --installation     # Check installation only")
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