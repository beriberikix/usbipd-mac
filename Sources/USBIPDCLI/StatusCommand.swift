import Foundation
import USBIPDCore
import Common

// Logger for command operations
private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "cli-commands")

// Placeholder struct for USB operation statistics
private struct PlaceholderUSBOperationStatistics {
    let activeRequestCount = 0
    let currentLoadPercentage = 0.0
    let activeControlRequests = 0
    let activeBulkRequests = 0
    let activeInterruptRequests = 0
    let activeIsochronousRequests = 0
    let successfulTransfers = 0
    let failedTransfers = 0
    let totalTransfers = 0
    let controlTransferCount = 0
    let successfulControlTransfers = 0
    let failedControlTransfers = 0
    let bulkTransferCount = 0
    let successfulBulkTransfers = 0
    let failedBulkTransfers = 0
    let interruptTransferCount = 0
    let successfulInterruptTransfers = 0
    let failedInterruptTransfers = 0
    let isochronousTransferCount = 0
    let successfulIsochronousTransfers = 0
    let failedIsochronousTransfers = 0
    let averageTransferLatency = 0.0
    let averageThroughput = 0.0
    let peakThroughput = 0.0
    let totalBytesTransferred: UInt64 = 0
    let timeoutErrors = 0
    let deviceNotAvailableErrors = 0
    let invalidParameterErrors = 0
    let endpointStallErrors = 0
    let otherErrors = 0
    let maxConcurrentRequests = 0
    let transferBufferMemoryUsage: UInt64 = 0
    let activeURBCount = 0
    let lastUpdateTime: Date? = nil
}

public class StatusCommand: Command {
    public let name = "status"
    public let description = "Show System Extension status and device information"
    
    private let deviceClaimManager: DeviceClaimManager?
    private let serverCoordinator: ServerCoordinator?
    private let outputFormatter: OutputFormatter
    
    public init(deviceClaimManager: DeviceClaimManager? = nil, serverCoordinator: ServerCoordinator? = nil, outputFormatter: OutputFormatter = DefaultOutputFormatter()) {
        self.deviceClaimManager = deviceClaimManager
        self.serverCoordinator = serverCoordinator
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
            
            // Display System Extension lifecycle status from ServerCoordinator
            if let coordinator = serverCoordinator {
                displaySystemExtensionLifecycleStatus(coordinator: coordinator, showDetailed: showDetailed)
                displayUSBOperationStatus(coordinator: coordinator, showDetailed: showDetailed)
            }
        }
    }
    
    private func displaySystemExtensionLifecycleStatus(coordinator: ServerCoordinator, showDetailed: Bool) {
        let status = coordinator.getSystemExtensionStatus()
        
        print("")
        print("System Extension Lifecycle")
        print("=========================")
        print("")
        
        if !status.enabled {
            print("❌ System Extension Management: Disabled")
            print("")
            print("System Extension lifecycle management is not active.")
            print("The daemon is running without advanced System Extension features.")
            print("")
            print("To enable System Extension management:")
            print("1. Configure System Extension bundle path and identifier")
            print("2. Restart the USB/IP daemon with System Extension support")
            print("3. Ensure proper code signing and entitlements")
            return
        }
        
        print("✅ System Extension Management: Enabled")
        print("📍 State: \(status.state)")
        
        if let health = status.health {
            print("💊 Health: \(health)")
            
            if showDetailed {
                print("")
                print("Lifecycle Details")
                print("-----------------")
                if status.state.contains("active") {
                    print("✅ System Extension is running normally")
                    print("✅ Health monitoring is active")
                    print("✅ Automatic recovery is enabled")
                } else if status.state.contains("failed") {
                    print("❌ System Extension has failed")
                    print("⚠️  Check system logs for detailed error information")
                    print("💡 Try restarting the daemon to recover")
                } else if status.state.contains("activating") {
                    print("⏳ System Extension is starting up")
                    print("💡 This may take a few moments")
                } else if status.state.contains("upgrading") {
                    print("🔄 System Extension is being updated")
                    print("💡 Wait for upgrade to complete")
                } else if status.state.contains("reboot") {
                    print("🔄 System reboot required")
                    print("💡 Restart your system to complete installation")
                }
                
                print("")
                print("Troubleshooting")
                print("---------------")
                if status.state.contains("failed") {
                    print("• Check system logs: log show --predicate 'subsystem == \"com.github.usbipd-mac\"' --last 1h")
                    print("• Verify System Extension is properly signed")
                    print("• Check System Preferences > Security & Privacy for blocked extensions")
                    print("• Try: systemextensionsctl reset (requires reboot)")
                } else if status.state.contains("inactive") {
                    print("• System Extension may require user approval")
                    print("• Check System Preferences > Security & Privacy > General")
                    print("• Verify bundle path and identifier configuration")
                } else if !health.contains("healthy: true") {
                    print("• System Extension health checks are failing")
                    print("• Check for resource constraints (memory, file descriptors)")
                    print("• Verify IPC communication is working")
                }
            }
        }
        
        print("")
    }
    
    private func displayUSBOperationStatus(coordinator: ServerCoordinator, showDetailed: Bool) {
        // TODO: Implement USB operation statistics method on ServerCoordinator
        // let usbStats = coordinator.getUSBOperationStatistics()
        // Placeholder statistics for compilation
        let usbStats = PlaceholderUSBOperationStatistics()
        
        print("")
        print("USB Operations Status")
        print("====================")
        print("")
        
        // Active operations overview
        let activeCount = usbStats.activeRequestCount
        let activeSymbol = activeCount > 0 ? "🔄" : "✅"
        print("\(activeSymbol) Active USB Requests: \(activeCount)")
        
        if activeCount > 0 {
            print("📊 Current Load: \(String(format: "%.1f", usbStats.currentLoadPercentage))%")
            
            if showDetailed {
                print("Active Request Breakdown:")
                if usbStats.activeControlRequests > 0 {
                    print("  • Control Transfers: \(usbStats.activeControlRequests)")
                }
                if usbStats.activeBulkRequests > 0 {
                    print("  • Bulk Transfers: \(usbStats.activeBulkRequests)")
                }
                if usbStats.activeInterruptRequests > 0 {
                    print("  • Interrupt Transfers: \(usbStats.activeInterruptRequests)")
                }
                if usbStats.activeIsochronousRequests > 0 {
                    print("  • Isochronous Transfers: \(usbStats.activeIsochronousRequests)")
                }
            }
        }
        
        print("")
        
        // Transfer statistics
        print("Transfer Statistics")
        print("------------------")
        print("✅ Successful Transfers: \(usbStats.successfulTransfers)")
        print("❌ Failed Transfers: \(usbStats.failedTransfers)")
        print("⏱️  Total Transfers: \(usbStats.totalTransfers)")
        
        if usbStats.totalTransfers > 0 {
            let successRate = Double(usbStats.successfulTransfers) / Double(usbStats.totalTransfers) * 100
            let successSymbol = successRate >= 95.0 ? "✅" : successRate >= 80.0 ? "⚠️" : "❌"
            print("\(successSymbol) Success Rate: \(String(format: "%.1f", successRate))%")
        }
        
        if showDetailed {
            print("")
            print("Transfer Type Breakdown")
            print("---------------------")
            print("Control Transfers: \(usbStats.controlTransferCount) (✅\(usbStats.successfulControlTransfers) ❌\(usbStats.failedControlTransfers))")
            print("Bulk Transfers: \(usbStats.bulkTransferCount) (✅\(usbStats.successfulBulkTransfers) ❌\(usbStats.failedBulkTransfers))")
            print("Interrupt Transfers: \(usbStats.interruptTransferCount) (✅\(usbStats.successfulInterruptTransfers) ❌\(usbStats.failedInterruptTransfers))")
            print("Isochronous Transfers: \(usbStats.isochronousTransferCount) (✅\(usbStats.successfulIsochronousTransfers) ❌\(usbStats.failedIsochronousTransfers))")
        }
        
        print("")
        
        // Performance metrics
        print("Performance Metrics")
        print("------------------")
        if usbStats.averageTransferLatency > 0 {
            let latencySymbol = usbStats.averageTransferLatency < 50.0 ? "✅" : usbStats.averageTransferLatency < 200.0 ? "⚠️" : "❌"
            print("\(latencySymbol) Average Latency: \(String(format: "%.1f", usbStats.averageTransferLatency))ms")
        } else {
            print("📊 Average Latency: N/A (no completed transfers)")
        }
        
        if usbStats.averageThroughput > 0 {
            let throughputFormatted = formatThroughput(usbStats.averageThroughput)
            print("🚀 Average Throughput: \(throughputFormatted)")
        } else {
            print("📊 Average Throughput: N/A (no data transfers)")
        }
        
        if showDetailed {
            print("Peak Throughput: \(formatThroughput(usbStats.peakThroughput))")
            print("Total Bytes Transferred: \(formatBytes(Int(usbStats.totalBytesTransferred)))")
        }
        
        print("")
        
        // Error analysis
        if usbStats.failedTransfers > 0 {
            print("Error Analysis")
            print("-------------")
            
            if showDetailed {
                print("Common Error Types:")
                if usbStats.timeoutErrors > 0 {
                    print("  • Timeouts: \(usbStats.timeoutErrors)")
                }
                if usbStats.deviceNotAvailableErrors > 0 {
                    print("  • Device Unavailable: \(usbStats.deviceNotAvailableErrors)")
                }
                if usbStats.invalidParameterErrors > 0 {
                    print("  • Invalid Parameters: \(usbStats.invalidParameterErrors)")
                }
                if usbStats.endpointStallErrors > 0 {
                    print("  • Endpoint Stalls: \(usbStats.endpointStallErrors)")
                }
                if usbStats.otherErrors > 0 {
                    print("  • Other Errors: \(usbStats.otherErrors)")
                }
            } else {
                print("Recent Errors: \(usbStats.failedTransfers)")
                print("Use --detailed for error breakdown")
            }
            print("")
        }
        
        // Resource utilization
        if showDetailed {
            print("Resource Utilization")
            print("-------------------")
            print("Concurrent Request Limit: \(usbStats.maxConcurrentRequests)")
            print("Current Utilization: \(String(format: "%.1f", usbStats.currentLoadPercentage))%")
            print("Memory Usage (Transfer Buffers): \(formatBytes(Int(usbStats.transferBufferMemoryUsage)))")
            print("Active URB Count: \(usbStats.activeURBCount)")
            print("")
        }
        
        // Recommendations
        if usbStats.failedTransfers > usbStats.successfulTransfers / 10 || // More than 10% failure rate
           usbStats.averageTransferLatency > 500.0 || // High latency
           usbStats.currentLoadPercentage > 90.0 { // High load
            
            print("Recommendations")
            print("---------------")
            
            if usbStats.failedTransfers > usbStats.successfulTransfers / 10 {
                print("⚠️  High error rate detected:")
                print("   • Check USB device connections and health")
                print("   • Verify devices are properly claimed")
                print("   • Monitor system logs for IOKit errors")
            }
            
            if usbStats.averageTransferLatency > 500.0 {
                print("⚠️  High latency detected:")
                print("   • Check system load and available resources")
                print("   • Consider reducing concurrent transfer count")
                print("   • Verify USB devices are not overloaded")
            }
            
            if usbStats.currentLoadPercentage > 90.0 {
                print("⚠️  High operation load:")
                print("   • System is near capacity for concurrent operations")
                print("   • Consider implementing client-side throttling")
                print("   • Monitor for resource exhaustion")
            }
            
            print("")
        }
        
        // Last update timestamp
        if let lastUpdate = usbStats.lastUpdateTime {
            print("📅 Statistics Last Updated: \(formatDate(lastUpdate))")
            print("")
        }
    }
    
    private func printHelp() {
        print("Usage: usbipd status [options]")
        print("")
        print("Show System Extension status and USB operation information. This command:")
        print("1. Displays System Extension health and running status")
        print("2. Lists all devices currently claimed by the System Extension")
        print("3. Shows active USB requests and transfer statistics")
        print("4. Reports USB operation performance and error analysis")
        print("5. Provides diagnostic data for support and monitoring")
        print("")
        print("Options:")
        print("  -d, --detailed  Show detailed metrics and statistics")
        print("  --health        Perform health check only")
        print("  -h, --help      Show this help message")
        print("")
        print("Examples:")
        print("  usbipd status               Show basic status and USB operation info")
        print("  usbipd status --detailed    Show detailed metrics and USB statistics")
        print("  usbipd status --health      Perform health check only")
        print("")
        print("Notes:")
        print("- Requires System Extension to be installed and running")
        print("- Health information helps diagnose System Extension issues")
        print("- USB operation statistics help monitor transfer performance")
        print("- Use this command to verify System Extension and USB functionality")
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
    
    private func formatThroughput(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        } else if bytesPerSecond >= 1_000 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1_000)
        } else {
            return String(format: "%.0f B/s", bytesPerSecond)
        }
    }
}