// ProcessHealthMonitor.swift
// Process health monitoring for System Extension

import Foundation
import Common

/// Monitor process health and responsiveness
public class ProcessHealthMonitor {
    
    // MARK: - Properties
    
    /// Logger for process monitoring
    private let logger: Logger
    
    /// Queue for process monitoring operations
    private let queue: DispatchQueue
    
    /// Whether monitoring is active
    private var isActive = false
    
    /// Process start time
    private let processStartTime = Date()
    
    /// Last responsiveness check time
    private var lastResponsivenessCheck = Date()
    
    /// Process responsiveness status
    private var isProcessResponsive = true
    
    /// Thread count tracking
    private var threadCountHistory: [Int] = []
    private let maxHistorySize = 10
    
    // MARK: - Initialization
    
    public init(logger: Logger) {
        self.logger = logger
        self.queue = DispatchQueue(
            label: "com.usbipd.mac.system-extension.process-monitor",
            qos: .utility
        )
    }
    
    // MARK: - Public Methods
    
    /// Start process monitoring
    public func startMonitoring() throws {
        queue.sync {
            guard !isActive else {
                logger.debug("Process monitoring already active")
                return
            }
            
            logger.debug("Starting process health monitoring")
            isActive = true
            
            // Initialize monitoring data
            updateResponsivenessStatus()
        }
    }
    
    /// Stop process monitoring
    public func stopMonitoring() {
        queue.sync {
            guard isActive else {
                logger.debug("Process monitoring not active")
                return
            }
            
            logger.debug("Stopping process health monitoring")
            isActive = false
            threadCountHistory.removeAll()
        }
    }
    
    /// Get current process health status
    public func getHealthStatus() -> ProcessHealthStatus {
        return queue.sync {
            updateResponsivenessStatus()
            return calculateProcessHealth()
        }
    }
    
    /// Get process uptime in seconds
    public func getUptime() -> TimeInterval {
        return queue.sync {
            return Date().timeIntervalSince(processStartTime)
        }
    }
    
    /// Perform responsiveness check
    public func checkResponsiveness() -> Bool {
        return queue.sync {
            updateResponsivenessStatus()
            return isProcessResponsive
        }
    }
    
    // MARK: - Private Implementation
    
    private func updateResponsivenessStatus() {
        let startTime = Date()
        
        // Simulate responsiveness check by performing a quick operation
        // In a real implementation, this might ping internal components
        let testOperation = performTestOperation()
        
        let responseTime = Date().timeIntervalSince(startTime)
        let wasResponsive = isProcessResponsive
        
        // Consider process responsive if test completes within reasonable time
        isProcessResponsive = testOperation && responseTime < 1.0 // 1 second threshold
        lastResponsivenessCheck = Date()
        
        // Log responsiveness changes
        if wasResponsive != isProcessResponsive {
            let status = isProcessResponsive ? "responsive" : "unresponsive"
            logger.info("Process responsiveness changed", context: [
                "status": status,
                "responseTime": String(format: "%.3f", responseTime)
            ])
        }
    }
    
    private func performTestOperation() -> Bool {
        // Simulate a quick internal operation to test responsiveness
        // This could be a ping to internal services, memory allocation test, etc.
        
        do {
            // Test basic system calls
            let _ = getpid()
            let _ = Date()
            
            // Test memory allocation
            let testData = Data(count: 1024)
            let _ = testData.count
            
            return true
        } catch {
            logger.debug("Test operation failed", context: ["error": error.localizedDescription])
            return false
        }
    }
    
    private func calculateProcessHealth() -> ProcessHealthStatus {
        var issues: [ProcessIssue] = []
        let currentThreadCount = getCurrentThreadCount()
        let processID = getpid()
        let mappedRegions = getMappedRegionsCount()
        
        // Update thread count history
        threadCountHistory.append(currentThreadCount)
        if threadCountHistory.count > maxHistorySize {
            threadCountHistory.removeFirst()
        }
        
        // Check for responsiveness issues
        if !isProcessResponsive {
            issues.append(ProcessIssue(
                type: .unresponsive,
                severity: .critical,
                description: "Process is not responding to health checks"
            ))
        }
        
        // Check for excessive thread count
        if currentThreadCount > 50 {
            issues.append(ProcessIssue(
                type: .highThreadCount,
                severity: .warning,
                description: "High thread count: \(currentThreadCount) threads"
            ))
        }
        
        // Check for potential memory leaks (increasing mapped regions)
        if mappedRegions > 1000 {
            issues.append(ProcessIssue(
                type: .memoryLeak,
                severity: .warning,
                description: "High mapped regions count: \(mappedRegions) regions"
            ))
        }
        
        // Check thread count trend for potential leaks
        if threadCountHistory.count >= 5 {
            let recentAverage = Double(threadCountHistory.suffix(3).reduce(0, +)) / 3.0
            let olderAverage = Double(threadCountHistory.prefix(3).reduce(0, +)) / 3.0
            
            if recentAverage > olderAverage * 1.5 {
                issues.append(ProcessIssue(
                    type: .highThreadCount,
                    severity: .warning,
                    description: "Thread count increasing trend detected"
                ))
            }
        }
        
        // Calculate health score
        let healthScore = calculateProcessHealthScore(
            isResponsive: isProcessResponsive,
            threadCount: currentThreadCount,
            mappedRegions: mappedRegions,
            issueCount: issues.count
        )
        
        return ProcessHealthStatus(
            uptime: getUptime(),
            processID: processID,
            threadCount: currentThreadCount,
            mappedRegions: mappedRegions,
            healthScore: healthScore,
            issues: issues,
            isResponsive: isProcessResponsive,
            lastResponseTime: lastResponsivenessCheck
        )
    }
    
    private func calculateProcessHealthScore(
        isResponsive: Bool,
        threadCount: Int,
        mappedRegions: Int,
        issueCount: Int
    ) -> Double {
        var score = 1.0
        
        // Responsiveness is critical
        if !isResponsive {
            score *= 0.0 // Critical failure
        }
        
        // Thread count impact
        if threadCount > 100 {
            score *= 0.3
        } else if threadCount > 50 {
            score *= 0.7
        } else if threadCount > 25 {
            score *= 0.9
        }
        
        // Mapped regions impact
        if mappedRegions > 2000 {
            score *= 0.5
        } else if mappedRegions > 1000 {
            score *= 0.8
        }
        
        // Issue count impact
        if issueCount > 2 {
            score *= 0.6
        } else if issueCount > 0 {
            score *= 0.8
        }
        
        return max(score, 0.0)
    }
    
    // MARK: - System Information Collection
    
    private func getCurrentThreadCount() -> Int {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        
        if result == KERN_SUCCESS {
            // Clean up the thread list
            if let threads = threadList {
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(threadCount * UInt32(MemoryLayout<thread_t>.size)))
            }
            return Int(threadCount)
        }
        
        return 0
    }
    
    private func getMappedRegionsCount() -> Int {
        // This is a simplified implementation
        // A real implementation would enumerate all mapped regions
        
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            // Return a reasonable estimate based on virtual size
            // In reality, you'd need to use vm_region to count actual regions
            return Int(info.virtual_size / (1024 * 1024)) // Rough estimate
        }
        
        return 0
    }
}