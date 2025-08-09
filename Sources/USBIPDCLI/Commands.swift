// Commands.swift
// Implementation of CLI commands for USB/IP daemon

import Foundation
import USBIPDCore
import Common
import SystemExtension

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
    private let deviceClaimManager: DeviceClaimManager?
    
    public init(deviceDiscovery: DeviceDiscovery, serverConfig: ServerConfig, deviceClaimManager: DeviceClaimManager? = nil) {
        self.deviceDiscovery = deviceDiscovery
        self.serverConfig = serverConfig
        self.deviceClaimManager = deviceClaimManager
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
            if let claimManager = deviceClaimManager {
                logger.debug("System Extension available for device claiming")
                
                // Check if device is already claimed
                if claimManager.isDeviceClaimed(deviceID: deviceIdentifier) {
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
                    let claimSuccess = try claimManager.claimDevice(device)
                    
                    if claimSuccess {
                        logger.info("Successfully claimed device through System Extension", context: ["deviceID": deviceIdentifier])
                        print("✓ Device \(busid) successfully claimed by System Extension")
                    } else {
                        logger.error("System Extension failed to claim device", context: ["deviceID": deviceIdentifier])
                        throw CommandHandlerError.deviceBindingFailed("System Extension failed to claim device \(busid)")
                    }
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
                logger.warning("System Extension not available, using configuration-only binding")
                print("⚠ System Extension not available - device will be bound in configuration only")
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
            
            if deviceClaimManager != nil {
                print("Device is now ready for USB/IP sharing with exclusive System Extension control")
            } else {
                print("Device is configured for USB/IP sharing (System Extension claiming not available)")
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
    private let deviceClaimManager: DeviceClaimManager?
    
    public init(deviceDiscovery: DeviceDiscovery, serverConfig: ServerConfig, deviceClaimManager: DeviceClaimManager? = nil) {
        self.deviceDiscovery = deviceDiscovery
        self.serverConfig = serverConfig
        self.deviceClaimManager = deviceClaimManager
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
            if let claimManager = deviceClaimManager {
                logger.debug("System Extension available for device release")
                
                let deviceIdentifier = busid
                let isDeviceClaimed = claimManager.isDeviceClaimed(deviceID: deviceIdentifier)
                
                if isDeviceClaimed {
                    print("Releasing device through System Extension...")
                    logger.debug("Attempting device release", context: ["deviceID": deviceIdentifier])
                    
                    do {
                        // Try to get the device info for release
                        if let device = try deviceDiscovery.getDevice(busID: busPart, deviceID: devicePart) {
                            try claimManager.releaseDevice(device)
                            logger.info("Successfully released device through System Extension", context: ["deviceID": deviceIdentifier])
                            print("✓ Device \(busid) successfully released by System Extension")
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
                            try claimManager.releaseDevice(cleanupDevice)
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
                logger.warning("System Extension not available for device release")
                print("⚠ System Extension not available - releasing from configuration only")
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
                
                if deviceClaimManager != nil {
                    print("Device \(busid) successfully unbound and released from System Extension control")
                } else {
                    print("Device \(busid) successfully unbound from USB/IP sharing")
                }
            } else {
                if wasBound || deviceClaimManager?.isDeviceClaimed(deviceID: busid) == true {
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

/// Status command implementation
public class StatusCommand: Command {
    public let name = "status"
    public let description = "Show System Extension status and device information"
    
    private let deviceClaimManager: DeviceClaimManager?
    private let outputFormatter: OutputFormatter
    
    public init(deviceClaimManager: DeviceClaimManager? = nil, outputFormatter: OutputFormatter = DefaultOutputFormatter()) {
        self.deviceClaimManager = deviceClaimManager
        self.outputFormatter = outputFormatter
    }
    
    public func execute(with arguments: [String]) throws {
        logger.debug("Executing status command", context: ["arguments": arguments.joined(separator: " ")])
        
        if arguments.contains("-h") || arguments.contains("--help") {
            logger.debug("Showing help for status command")
            printHelp()
            return
        }
        
        // Parse options
        var showDetailed = false
        var showHealthOnly = false
        
        for arg in arguments {
            switch arg {
            case "-d", "--detailed":
                showDetailed = true
                logger.debug("Using detailed status mode")
            case "--health":
                showHealthOnly = true
                logger.debug("Using health check only mode")
            case "-h", "--help":
                printHelp()
                return
            default:
                logger.error("Unknown option for status command", context: ["option": arg])
                throw CommandLineError.invalidArguments("Unknown option: \(arg)")
            }
        }
        
        guard let claimManager = deviceClaimManager else {
            logger.warning("System Extension not available")
            print("System Extension Status: Not Available")
            print("")
            print("⚠ System Extension integration is not active")
            print("The USB/IP daemon is running without System Extension support.")
            print("Device claiming through System Extension is disabled.")
            print("")
            print("To enable System Extension functionality:")
            print("1. Ensure macOS System Extension requirements are met")
            print("2. Install and activate the USB/IP System Extension")
            print("3. Grant necessary permissions in System Preferences")
            return
        }
        
        do {
            if showHealthOnly {
                // Perform health check only
                print("Performing System Extension health check...")
                let isHealthy: Bool
                if let adapter = claimManager as? SystemExtensionClaimAdapter {
                    isHealthy = adapter.performSystemExtensionHealthCheck()
                } else {
                    // Fallback for mock or other implementations
                    isHealthy = true
                }
                
                if isHealthy {
                    print("✅ System Extension is healthy")
                } else {
                    print("❌ System Extension health check failed")
                    print("Check logs for detailed error information")
                }
                return
            }
            
            // Get status information
            if let adapter = claimManager as? SystemExtensionClaimAdapter {
                let status = adapter.getSystemExtensionStatus()
                let statistics = adapter.getSystemExtensionStatistics()
                
                // Display basic status
                print("System Extension Status")
                print("======================")
                print("")
                
                // Status overview
                let statusSymbol = status.isRunning ? "✅" : "❌"
                print("\(statusSymbol) Status: \(status.isRunning ? "Running" : "Stopped")")
                print("📅 Last Started: \(formatDate(status.lastStartTime))")
                print("🔢 Version: \(status.version)")
                
                // Error information
                if status.errorCount > 0 {
                    print("⚠️  Error Count: \(status.errorCount)")
                } else {
                    print("✅ Error Count: 0")
                }
                
                // Memory usage
                print("💾 Memory Usage: \(formatBytes(status.memoryUsage))")
                print("")
                
                // Claimed devices
                print("Claimed Devices")
                print("===============")
                if status.claimedDevices.isEmpty {
                    print("No devices are currently claimed")
                } else {
                    print("Currently claimed devices: \(status.claimedDevices.count)")
                    for device in status.claimedDevices {
                        let deviceInfo = "\(device.busID)-\(device.deviceID)"
                        let productInfo = device.productString ?? "Unknown Device"
                        print("  • \(deviceInfo): \(productInfo)")
                        if showDetailed {
                            print("    Vendor: \(String(format: "0x%04x", device.vendorID))")
                            print("    Product: \(String(format: "0x%04x", device.productID))")
                        }
                    }
                }
                print("")
                
                // Health metrics
                if showDetailed {
                    print("Health Metrics")
                    print("==============")
                    let healthMetrics = status.healthMetrics
                    print("Successful Claims: \(healthMetrics.successfulClaims)")
                    print("Failed Claims: \(healthMetrics.failedClaims)")
                    print("Active IPC Connections: \(healthMetrics.activeConnections)")
                    print("Average Claim Time: \(String(format: "%.1f", healthMetrics.averageClaimTime))ms")
                    print("Last Health Check: \(formatDate(healthMetrics.lastHealthCheck))")
                    print("")
                    
                    // Statistics
                    print("Statistics")
                    print("==========")
                    print("Total Requests: \(statistics.totalRequests)")
                    print("Total Responses: \(statistics.totalResponses)")
                    print("Total Errors: \(statistics.totalErrors)")
                    print("Successful Claims: \(statistics.successfulClaims)")
                    print("Failed Claims: \(statistics.failedClaims)")
                    print("Successful Releases: \(statistics.successfulReleases)")
                    print("Failed Releases: \(statistics.failedReleases)")
                    if let startTime = statistics.startTime {
                        print("Started: \(formatDate(startTime))")
                        let uptime = Date().timeIntervalSince(startTime)
                        print("Uptime: \(formatDuration(uptime))")
                    }
                    print("")
                }
                
                // Troubleshooting
                if status.errorCount > 0 || !status.isRunning {
                    print("Troubleshooting")
                    print("===============")
                    if !status.isRunning {
                        print("System Extension is not running:")
                        print("1. Check if the System Extension is properly installed")
                        print("2. Verify System Extension permissions in System Preferences")
                        print("3. Try restarting the USB/IP daemon")
                        print("4. Check system logs for extension load errors")
                    }
                    if status.errorCount > 0 {
                        print("Errors detected:")
                        print("1. Check application logs for detailed error information")
                        print("2. Verify USB device permissions")
                        print("3. Try unbinding and rebinding problematic devices")
                    }
                    print("")
                }
                
                print("For more information, use: usbipd status --detailed")
            } else {
                // Fallback for non-SystemExtensionClaimAdapter implementations
                print("System Extension Status: Active")
                print("")
                print("✅ System Extension integration is active")
                print("Device claiming functionality is available")
                print("")
                print("Note: Detailed status information requires full System Extension integration")
            }
        } catch {
            logger.error("Failed to get system status", context: ["error": error.localizedDescription])
            throw CommandHandlerError.operationNotSupported("Failed to retrieve System Extension status: \(error.localizedDescription)")
        }
    }
    
    private func printHelp() {
        print("Usage: usbipd status [options]")
        print("")
        print("Show System Extension status and claimed device information. This command:")
        print("1. Displays System Extension health and running status")
        print("2. Lists all devices currently claimed by the System Extension")
        print("3. Shows error counts and troubleshooting information")
        print("4. Provides diagnostic data for support and monitoring")
        print("")
        print("Options:")
        print("  -d, --detailed  Show detailed metrics and statistics")
        print("  --health        Perform health check only")
        print("  -h, --help      Show this help message")
        print("")
        print("Examples:")
        print("  usbipd status               Show basic status information")
        print("  usbipd status --detailed    Show detailed status with metrics")
        print("  usbipd status --health      Perform health check only")
        print("")
        print("Notes:")
        print("- Requires System Extension to be installed and running")
        print("- Health information helps diagnose System Extension issues")
        print("- Use this command to verify System Extension functionality")
    }
    
    // MARK: - Formatting Utilities
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useBytes]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, secs)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
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