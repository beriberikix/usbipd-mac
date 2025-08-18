// ServiceLifecycleManager.swift
// Service lifecycle manager for launchd integration and coordination

import Foundation
import Common

/// Manager for coordinating System Extension installation with service lifecycle
public final class ServiceLifecycleManager: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.github.usbipd-mac", category: "ServiceLifecycleManager")
    
    /// Service identifier for usbipd-mac
    private static let serviceIdentifier = "com.github.usbipd-mac"
    
    /// Homebrew formula name
    private static let formulaName = "usbipd-mac"
    
    /// Default homebrew prefix
    private let homebrewPrefix: String
    
    // MARK: - Initialization
    
    /// Initialize service lifecycle manager
    /// - Parameter homebrewPrefix: Custom homebrew prefix (defaults to /opt/homebrew)
    public init(homebrewPrefix: String? = nil) {
        self.homebrewPrefix = homebrewPrefix ?? "/opt/homebrew"
        logger.info("ServiceLifecycleManager initialized", context: [
            "homebrewPrefix": self.homebrewPrefix
        ])
    }
    
    // MARK: - Public Interface
    
    /// Integrate System Extension installation with launchd service registration
    /// - Returns: Integration result with status and recommendations
    public func integrateWithLaunchd() async -> ServiceIntegrationResult {
        logger.info("Starting launchd integration")
        
        var issues: [ServiceIssue] = []
        var recommendations: [String] = []
        
        // Check if service is registered with launchd
        let launchdStatus = await checkLaunchdRegistration()
        if !launchdStatus.isRegistered {
            issues.append(.serviceNotRegistered)
            recommendations.append("Register service with launchd using: sudo launchctl load <plist>")
        }
        
        // Check service status
        let serviceStatus = await detectServiceStatus()
        
        // Analyze service health
        if serviceStatus.hasOrphanedProcesses {
            issues.append(.orphanedProcesses)
            recommendations.append("Clean up orphaned processes before System Extension installation")
        }
        
        if serviceStatus.hasPortConflicts {
            issues.append(.portConflicts)
            recommendations.append("Resolve port conflicts on default USB/IP port 3240")
        }
        
        let integrationStatus = ServiceIntegrationStatus(
            launchdRegistered: launchdStatus.isRegistered,
            serviceRunning: serviceStatus.isRunning,
            brewServicesManaged: serviceStatus.isManagedByBrew,
            orphanedProcesses: serviceStatus.orphanedProcessCount,
            lastError: serviceStatus.lastError
        )
        
        logger.info("Launchd integration completed", context: [
            "registered": launchdStatus.isRegistered,
            "running": serviceStatus.isRunning,
            "issues": issues.count
        ])
        
        return ServiceIntegrationResult(
            success: issues.isEmpty,
            status: integrationStatus,
            issues: issues,
            recommendations: recommendations
        )
    }
    
    /// Coordinate System Extension installation with service lifecycle
    /// - Parameters:
    ///   - preInstallation: Called before System Extension installation
    ///   - postInstallation: Called after System Extension installation
    /// - Returns: Coordination result
    public func coordinateInstallationWithService(
        preInstallation: (() async -> Void)? = nil,
        postInstallation: (() async -> Void)? = nil
    ) async -> ServiceCoordinationResult {
        logger.info("Starting installation coordination with service lifecycle")
        
        var warnings: [String] = []
        var errors: [ServiceIssue] = []
        
        // Step 1: Pre-installation service checks
        let preServiceStatus = await detectServiceStatus()
        
        // Stop service if running to avoid conflicts
        if preServiceStatus.isRunning {
            logger.info("Stopping service before System Extension installation")
            let stopResult = await stopService()
            if !stopResult.success {
                errors.append(.serviceStopFailed)
                warnings.append("Failed to stop service before installation: \(stopResult.error?.localizedDescription ?? "Unknown error")")
            } else {
                warnings.append("Service was stopped for System Extension installation")
            }
        }
        
        // Clean up orphaned processes
        if preServiceStatus.hasOrphanedProcesses {
            logger.info("Cleaning up orphaned processes")
            let cleanupResult = await resolveServiceConflicts()
            if cleanupResult.processesTerminated > 0 {
                warnings.append("Terminated \(cleanupResult.processesTerminated) orphaned processes")
            }
        }
        
        // Step 2: Execute pre-installation callback
        await preInstallation?()
        
        // Step 3: Wait for System Extension to be ready (this would be called by the installer)
        // Note: This is a coordination point - the actual installation happens elsewhere
        
        // Step 4: Execute post-installation callback
        await postInstallation?()
        
        // Step 5: Verify service integration after installation
        let integrationResult = await integrateWithLaunchd()
        if !integrationResult.success {
            errors.append(contentsOf: integrationResult.issues)
        }
        
        // Step 6: Restart service if it was running before
        if preServiceStatus.isRunning && errors.isEmpty {
            logger.info("Restarting service after System Extension installation")
            let startResult = await startService()
            if !startResult.success {
                errors.append(.serviceStartFailed)
                warnings.append("Failed to restart service after installation: \(startResult.error?.localizedDescription ?? "Unknown error")")
            } else {
                warnings.append("Service restarted successfully")
            }
        }
        
        let coordinationStatus = ServiceCoordinationStatus(
            coordinationSuccessful: errors.isEmpty,
            serviceWasRunning: preServiceStatus.isRunning,
            serviceRestartRequired: preServiceStatus.isRunning && !errors.isEmpty,
            cleanupPerformed: preServiceStatus.hasOrphanedProcesses
        )
        
        logger.info("Installation coordination completed", context: [
            "successful": errors.isEmpty,
            "warnings": warnings.count,
            "errors": errors.count
        ])
        
        return ServiceCoordinationResult(
            success: errors.isEmpty,
            status: coordinationStatus,
            issues: errors,
            warnings: warnings
        )
    }
    
    /// Verify service management integration with brew services
    /// - Returns: Verification result
    public func verifyServiceManagement() async -> ServiceVerificationResult {
        logger.info("Verifying service management integration")
        
        var validationChecks: [ServiceValidationCheck] = []
        
        // Check 1: Brew services status
        let brewStatus = await checkBrewServicesStatus()
        validationChecks.append(ServiceValidationCheck(
            checkID: "brew_services_status",
            checkName: "Homebrew Services Status",
            passed: brewStatus.isAvailable,
            message: brewStatus.isAvailable ? "Brew services is available" : "Brew services not available",
            severity: brewStatus.isAvailable ? .info : .warning,
            details: brewStatus.statusOutput
        ))
        
        // Check 2: Service registration
        let registration = await checkLaunchdRegistration()
        validationChecks.append(ServiceValidationCheck(
            checkID: "service_registration",
            checkName: "Service Registration",
            passed: registration.isRegistered,
            message: registration.isRegistered ? "Service is registered with launchd" : "Service not registered",
            severity: registration.isRegistered ? .info : .error,
            details: registration.registrationInfo
        ))
        
        // Check 3: Service configuration
        let configCheck = await validateServiceConfiguration()
        validationChecks.append(configCheck)
        
        // Check 4: Port availability
        let portCheck = await checkPortAvailability()
        validationChecks.append(portCheck)
        
        // Check 5: Process health
        let processCheck = await checkProcessHealth()
        validationChecks.append(processCheck)
        
        let overallHealth = determineServiceHealth(from: validationChecks)
        
        logger.info("Service management verification completed", context: [
            "health": overallHealth.rawValue,
            "checks": validationChecks.count,
            "passed": validationChecks.filter { $0.passed }.count
        ])
        
        return ServiceVerificationResult(
            overallHealth: overallHealth,
            validationChecks: validationChecks,
            timestamp: Date()
        )
    }
    
    // MARK: - Service Status Detection
    
    /// Detect current service status using multiple detection methods
    /// - Returns: Comprehensive service status
    public func detectServiceStatus() async -> DetailedServiceStatus {
        logger.debug("Detecting service status")
        
        // Check launchctl status
        let launchdResult = await executeLaunchctl(command: "list", arguments: [Self.serviceIdentifier])
        let isRunningViaLaunchd = launchdResult.success && 
                                 launchdResult.output.contains("PID") && 
                                 !launchdResult.output.contains("PID = 0")
        
        // Check brew services status
        let brewResult = await executeBrewServices(command: "list")
        let isManagedByBrew = brewResult.success && brewResult.output.contains(Self.formulaName)
        let isRunningViaBrew = isManagedByBrew && brewResult.output.contains("started")
        
        // Check for orphaned processes
        let orphanedProcesses = await findOrphanedProcesses()
        
        // Check port conflicts
        let portConflicts = await checkForPortConflicts()
        
        // Determine overall running status
        let isRunning = isRunningViaLaunchd || isRunningViaBrew || !orphanedProcesses.isEmpty
        
        return DetailedServiceStatus(
            isRunning: isRunning,
            isManagedByBrew: isManagedByBrew,
            isRegisteredWithLaunchd: launchdResult.success,
            orphanedProcessCount: orphanedProcesses.count,
            hasPortConflicts: !portConflicts.isEmpty,
            lastError: !launchdResult.success ? launchdResult.error : nil,
            statusDetails: ServiceStatusDetails(
                launchdOutput: launchdResult.output,
                brewServicesOutput: brewResult.output,
                orphanedProcesses: orphanedProcesses,
                portConflicts: portConflicts
            )
        )
    }
    
    /// Resolve service conflicts by cleaning up orphaned processes
    /// - Returns: Cleanup result with details
    public func resolveServiceConflicts() async -> ServiceConflictResolution {
        logger.info("Resolving service conflicts")
        
        let orphanedProcesses = await findOrphanedProcesses()
        var terminatedProcesses = 0
        var failures: [String] = []
        
        for process in orphanedProcesses {
            logger.debug("Attempting to terminate orphaned process", context: ["pid": process.pid])
            
            let result = await executeCommand(
                executable: "/bin/kill",
                arguments: ["-TERM", String(process.pid)]
            )
            
            if result.success {
                terminatedProcesses += 1
                logger.info("Terminated orphaned process", context: ["pid": process.pid])
            } else {
                failures.append("Failed to terminate PID \(process.pid): \(result.error?.localizedDescription ?? "Unknown error")")
            }
        }
        
        // Wait a moment for graceful termination
        if terminatedProcesses > 0 {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        }
        
        // Force kill any remaining processes
        let remainingProcesses = await findOrphanedProcesses()
        for process in remainingProcesses {
            logger.warning("Force killing remaining process", context: ["pid": process.pid])
            
            let result = await executeCommand(
                executable: "/bin/kill",
                arguments: ["-KILL", String(process.pid)]
            )
            
            if result.success {
                terminatedProcesses += 1
            } else {
                failures.append("Failed to force kill PID \(process.pid): \(result.error?.localizedDescription ?? "Unknown error")")
            }
        }
        
        logger.info("Service conflict resolution completed", context: [
            "terminated": terminatedProcesses,
            "failures": failures.count
        ])
        
        return ServiceConflictResolution(
            processesTerminated: terminatedProcesses,
            failures: failures,
            success: failures.isEmpty
        )
    }
    
    // MARK: - Service Control
    
    /// Start the service using brew services
    /// - Returns: Start operation result
    public func startService() async -> ServiceOperationResult {
        logger.info("Starting service via brew services")
        
        let result = await executeBrewServices(command: "start", arguments: [Self.formulaName])
        
        if result.success {
            logger.info("Service started successfully")
            return ServiceOperationResult(success: true, output: result.output)
        } else {
            logger.error("Failed to start service", context: ["error": result.error?.localizedDescription ?? "Unknown"])
            return ServiceOperationResult(
                success: false,
                output: result.output,
                error: result.error
            )
        }
    }
    
    /// Stop the service using brew services
    /// - Returns: Stop operation result
    public func stopService() async -> ServiceOperationResult {
        logger.info("Stopping service via brew services")
        
        let result = await executeBrewServices(command: "stop", arguments: [Self.formulaName])
        
        if result.success {
            logger.info("Service stopped successfully")
            return ServiceOperationResult(success: true, output: result.output)
        } else {
            logger.error("Failed to stop service", context: ["error": result.error?.localizedDescription ?? "Unknown"])
            return ServiceOperationResult(
                success: false,
                output: result.output,
                error: result.error
            )
        }
    }
    
    /// Restart the service using brew services
    /// - Returns: Restart operation result
    public func restartService() async -> ServiceOperationResult {
        logger.info("Restarting service via brew services")
        
        let result = await executeBrewServices(command: "restart", arguments: [Self.formulaName])
        
        if result.success {
            logger.info("Service restarted successfully")
            return ServiceOperationResult(success: true, output: result.output)
        } else {
            logger.error("Failed to restart service", context: ["error": result.error?.localizedDescription ?? "Unknown"])
            return ServiceOperationResult(
                success: false,
                output: result.output,
                error: result.error
            )
        }
    }
    
    // MARK: - Private Helpers
    
    private func checkLaunchdRegistration() async -> LaunchdRegistrationStatus {
        let result = await executeLaunchctl(command: "list", arguments: [Self.serviceIdentifier])
        
        return LaunchdRegistrationStatus(
            isRegistered: result.success,
            registrationInfo: result.output
        )
    }
    
    private func checkBrewServicesStatus() async -> BrewServicesStatus {
        let result = await executeBrewServices(command: "list")
        
        let isAvailable = result.success
        let containsFormula = result.output.contains(Self.formulaName)
        
        return BrewServicesStatus(
            isAvailable: isAvailable,
            formulaManaged: containsFormula,
            statusOutput: result.output
        )
    }
    
    private func findOrphanedProcesses() async -> [OrphanedProcess] {
        // Find processes with "usbipd" in the name that might be orphaned
        let result = await executeCommand(
            executable: "/bin/ps",
            arguments: ["-ax", "-o", "pid,ppid,command"]
        )
        
        guard result.success else { return [] }
        
        var orphanedProcesses: [OrphanedProcess] = []
        let lines = result.output.components(separatedBy: .newlines)
        
        for line in lines {
            if line.contains("usbipd") && !line.contains("grep") {
                let components = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
                if components.count >= 3,
                   let pid = Int(components[0]),
                   let ppid = Int(components[1]) {
                    
                    let command = components[2...].joined(separator: " ")
                    orphanedProcesses.append(OrphanedProcess(
                        pid: pid,
                        ppid: ppid,
                        command: command
                    ))
                }
            }
        }
        
        return orphanedProcesses
    }
    
    private func checkForPortConflicts() async -> [PortConflict] {
        // Check if port 3240 (default USB/IP port) is in use
        let result = await executeCommand(
            executable: "/usr/sbin/lsof",
            arguments: ["-i", ":3240"]
        )
        
        guard result.success && !result.output.isEmpty else { return [] }
        
        var conflicts: [PortConflict] = []
        let lines = result.output.components(separatedBy: .newlines)
        
        for line in lines.dropFirst() { // Skip header
            if !line.isEmpty {
                let components = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
                if components.count >= 2 {
                    conflicts.append(PortConflict(
                        port: 3240,
                        process: components[0],
                        pid: components[1]
                    ))
                }
            }
        }
        
        return conflicts
    }
    
    private func validateServiceConfiguration() async -> ServiceValidationCheck {
        // Check if the service plist exists and is valid
        let plistPaths = [
            "/Library/LaunchDaemons/\(Self.serviceIdentifier).plist",
            "\(homebrewPrefix)/etc/\(Self.formulaName)/\(Self.serviceIdentifier).plist"
        ]
        
        for path in plistPaths {
            if FileManager.default.fileExists(atPath: path) {
                return ServiceValidationCheck(
                    checkID: "service_configuration",
                    checkName: "Service Configuration",
                    passed: true,
                    message: "Service plist found at \(path)",
                    severity: .info,
                    details: path
                )
            }
        }
        
        return ServiceValidationCheck(
            checkID: "service_configuration",
            checkName: "Service Configuration",
            passed: false,
            message: "No service plist found",
            severity: .warning,
            details: "Checked paths: \(plistPaths.joined(separator: ", "))"
        )
    }
    
    private func checkPortAvailability() async -> ServiceValidationCheck {
        let conflicts = await checkForPortConflicts()
        
        if conflicts.isEmpty {
            return ServiceValidationCheck(
                checkID: "port_availability",
                checkName: "Port Availability",
                passed: true,
                message: "Port 3240 is available",
                severity: .info,
                details: "No conflicts detected"
            )
        } else {
            return ServiceValidationCheck(
                checkID: "port_availability",
                checkName: "Port Availability",
                passed: false,
                message: "Port 3240 conflicts detected",
                severity: .error,
                details: "Conflicts: \(conflicts.map { "\($0.process) (PID: \($0.pid))" }.joined(separator: ", "))"
            )
        }
    }
    
    private func checkProcessHealth() async -> ServiceValidationCheck {
        let orphaned = await findOrphanedProcesses()
        
        if orphaned.isEmpty {
            return ServiceValidationCheck(
                checkID: "process_health",
                checkName: "Process Health",
                passed: true,
                message: "No orphaned processes detected",
                severity: .info,
                details: "Process tree is clean"
            )
        } else {
            return ServiceValidationCheck(
                checkID: "process_health",
                checkName: "Process Health",
                passed: false,
                message: "\(orphaned.count) orphaned processes detected",
                severity: .warning,
                details: "Orphaned PIDs: \(orphaned.map { String($0.pid) }.joined(separator: ", "))"
            )
        }
    }
    
    private func determineServiceHealth(from checks: [ServiceValidationCheck]) -> ServiceHealth {
        let criticalFailures = checks.filter { !$0.passed && $0.severity == .critical }
        let errorFailures = checks.filter { !$0.passed && $0.severity == .error }
        let warnings = checks.filter { !$0.passed && $0.severity == .warning }
        
        if !criticalFailures.isEmpty {
            return .critical
        } else if !errorFailures.isEmpty {
            return .unhealthy
        } else if !warnings.isEmpty {
            return .degraded
        } else {
            return .healthy
        }
    }
    
    // MARK: - Command Execution
    
    private func executeLaunchctl(command: String, arguments: [String] = []) async -> CommandResult {
        await executeCommand(
            executable: "/bin/launchctl",
            arguments: [command] + arguments
        )
    }
    
    private func executeBrewServices(command: String, arguments: [String] = []) async -> CommandResult {
        await executeCommand(
            executable: "brew",
            arguments: ["services", command] + arguments
        )
    }
    
    private func executeCommand(executable: String, arguments: [String]) async -> CommandResult {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            process.terminationHandler = { process in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                
                let success = process.terminationStatus == 0
                let error = success ? nil : NSError(
                    domain: "ServiceLifecycleManager",
                    code: Int(process.terminationStatus),
                    userInfo: [
                        NSLocalizedDescriptionKey: errorOutput.isEmpty ? "Command failed" : errorOutput
                    ]
                )
                
                continuation.resume(returning: CommandResult(
                    success: success,
                    output: output,
                    error: error
                ))
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(returning: CommandResult(
                    success: false,
                    output: "",
                    error: error
                ))
            }
        }
    }
}

// MARK: - Command Result Helper

private struct CommandResult {
    let success: Bool
    let output: String
    let error: Error?
}