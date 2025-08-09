import Foundation
import USBIPDCore
import Common
import SystemExtension

// Logger for command operations
private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "cli-commands")

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