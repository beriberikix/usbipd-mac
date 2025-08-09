// SystemResourceMonitor.swift
// System resource monitoring for health checks

import Foundation
import Common

/// Monitor system resource usage for health assessments
public class SystemResourceMonitor {
    
    // MARK: - Properties
    
    /// Logger for resource monitoring
    private let logger: Logger
    
    /// Queue for resource monitoring operations
    private let queue: DispatchQueue
    
    /// Whether monitoring is active
    private var isActive = false
    
    /// Cached resource data
    private var cachedResourceData: ResourceData?
    private var lastCacheUpdate: Date?
    
    /// Cache timeout in seconds
    private let cacheTimeout: TimeInterval = 2.0
    
    // MARK: - Initialization
    
    public init(logger: Logger) {
        self.logger = logger
        self.queue = DispatchQueue(
            label: "com.usbipd.mac.system-extension.resource-monitor",
            qos: .utility
        )
    }
    
    // MARK: - Public Methods
    
    /// Start resource monitoring
    public func startMonitoring() throws {
        queue.sync {
            guard !isActive else {
                logger.debug("Resource monitoring already active")
                return
            }
            
            logger.debug("Starting system resource monitoring")
            isActive = true
            
            // Perform initial resource collection
            updateResourceCache()
        }
    }
    
    /// Stop resource monitoring
    public func stopMonitoring() {
        queue.sync {
            guard isActive else {
                logger.debug("Resource monitoring not active")
                return
            }
            
            logger.debug("Stopping system resource monitoring")
            isActive = false
            cachedResourceData = nil
            lastCacheUpdate = nil
        }
    }
    
    /// Get current resource health status
    public func getHealthStatus() -> ResourceHealthStatus {
        return queue.sync {
            let resourceData = getCurrentResourceData()
            return calculateResourceHealth(from: resourceData)
        }
    }
    
    /// Get total system memory in bytes
    public func getTotalMemory() -> UInt64 {
        return queue.sync {
            return getCurrentResourceData().totalMemory
        }
    }
    
    /// Get available system memory in bytes
    public func getAvailableMemory() -> UInt64 {
        return queue.sync {
            return getCurrentResourceData().availableMemory
        }
    }
    
    /// Get system load average
    public func getLoadAverage() -> Double {
        return queue.sync {
            return getCurrentResourceData().loadAverage
        }
    }
    
    // MARK: - Private Implementation
    
    private func getCurrentResourceData() -> ResourceData {
        // Check if cached data is still valid
        if let cached = cachedResourceData,
           let lastUpdate = lastCacheUpdate,
           Date().timeIntervalSince(lastUpdate) < cacheTimeout {
            return cached
        }
        
        // Update cache with fresh data
        updateResourceCache()
        return cachedResourceData ?? ResourceData()
    }
    
    private func updateResourceCache() {
        let startTime = Date()
        
        let resourceData = ResourceData(
            memoryUsage: getCurrentMemoryUsage(),
            totalMemory: getTotalSystemMemory(),
            availableMemory: getAvailableSystemMemory(),
            cpuUsage: getCurrentCPUUsage(),
            loadAverage: getSystemLoadAverage(),
            availableDiskSpace: getAvailableDiskSpace(),
            openFileDescriptors: getOpenFileDescriptorCount()
        )
        
        cachedResourceData = resourceData
        lastCacheUpdate = Date()
        
        let updateDuration = Date().timeIntervalSince(startTime) * 1000
        logger.debug("Resource cache updated", context: [
            "memoryMB": String(format: "%.1f", resourceData.memoryUsage),
            "cpuPercent": String(format: "%.1f", resourceData.cpuUsage * 100),
            "updateDuration": String(format: "%.2f", updateDuration)
        ])
    }
    
    private func calculateResourceHealth(from data: ResourceData) -> ResourceHealthStatus {
        var issues: [ResourceIssue] = []
        var scores: [Double] = []
        
        // Memory usage assessment
        let memoryPercent = data.totalMemory > 0 ? Double(data.memoryUsage) / Double(data.totalMemory) * 100.0 : 0.0
        let memoryScore = calculateMemoryScore(usage: data.memoryUsage, percent: memoryPercent)
        scores.append(memoryScore)
        
        if memoryPercent > 90.0 {
            issues.append(ResourceIssue(
                type: .memoryUsage,
                severity: .critical,
                description: "Memory usage critically high: \(String(format: "%.1f", memoryPercent))%",
                value: memoryPercent,
                threshold: 90.0
            ))
        } else if memoryPercent > 75.0 {
            issues.append(ResourceIssue(
                type: .memoryUsage,
                severity: .warning,
                description: "Memory usage high: \(String(format: "%.1f", memoryPercent))%",
                value: memoryPercent,
                threshold: 75.0
            ))
        }
        
        // CPU usage assessment
        let cpuScore = calculateCPUScore(usage: data.cpuUsage)
        scores.append(cpuScore)
        
        if data.cpuUsage > 0.9 {
            issues.append(ResourceIssue(
                type: .cpuUsage,
                severity: .critical,
                description: "CPU usage critically high: \(String(format: "%.1f", data.cpuUsage * 100))%",
                value: data.cpuUsage * 100,
                threshold: 90.0
            ))
        } else if data.cpuUsage > 0.75 {
            issues.append(ResourceIssue(
                type: .cpuUsage,
                severity: .warning,
                description: "CPU usage high: \(String(format: "%.1f", data.cpuUsage * 100))%",
                value: data.cpuUsage * 100,
                threshold: 75.0
            ))
        }
        
        // Load average assessment
        let loadScore = calculateLoadAverageScore(loadAverage: data.loadAverage)
        scores.append(loadScore)
        
        // Disk space assessment
        let diskScore = calculateDiskSpaceScore(availableSpace: data.availableDiskSpace)
        scores.append(diskScore)
        
        if data.availableDiskSpace < 1.0 {
            issues.append(ResourceIssue(
                type: .diskSpace,
                severity: .critical,
                description: "Disk space critically low: \(String(format: "%.2f", data.availableDiskSpace))GB",
                value: data.availableDiskSpace,
                threshold: 1.0
            ))
        }
        
        // File descriptor assessment
        let fdScore = calculateFileDescriptorScore(openFDs: data.openFileDescriptors)
        scores.append(fdScore)
        
        // Calculate overall resource health score
        let overallScore = scores.reduce(0.0, +) / Double(scores.count)
        
        return ResourceHealthStatus(
            memoryUsage: data.memoryUsage,
            memoryUsagePercent: memoryPercent,
            cpuUsage: data.cpuUsage,
            loadAverage: data.loadAverage,
            availableDiskSpace: data.availableDiskSpace,
            openFileDescriptors: data.openFileDescriptors,
            healthScore: overallScore,
            issues: issues
        )
    }
    
    // MARK: - System Resource Collection
    
    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Double(info.resident_size) / (1024.0 * 1024.0) // Convert to MB
        }
        
        return 0.0
    }
    
    private func getTotalSystemMemory() -> UInt64 {
        var size = MemoryLayout<UInt64>.size
        var totalMemory: UInt64 = 0
        
        if sysctlbyname("hw.memsize", &totalMemory, &size, nil, 0) == 0 {
            return totalMemory
        }
        
        return 0
    }
    
    private func getAvailableSystemMemory() -> UInt64 {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let pageSize = vm_kernel_page_size
            let freePages = UInt64(vmStats.free_count)
            return freePages * UInt64(pageSize)
        }
        
        return 0
    }
    
    private func getCurrentCPUUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            // This is a simplified CPU usage calculation
            // In a real implementation, you would track CPU time over intervals
            return min(Double(info.virtual_size) / Double(getTotalSystemMemory()), 1.0)
        }
        
        return 0.0
    }
    
    private func getSystemLoadAverage() -> Double {
        var loadAverage: [Double] = [0.0, 0.0, 0.0]
        
        if getloadavg(&loadAverage, 3) != -1 {
            return loadAverage[0] // 1-minute load average
        }
        
        return 0.0
    }
    
    private func getAvailableDiskSpace() -> Double {
        do {
            let url = URL(fileURLWithPath: "/")
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            
            if let availableCapacity = values.volumeAvailableCapacity {
                return Double(availableCapacity) / (1024.0 * 1024.0 * 1024.0) // Convert to GB
            }
        } catch {
            logger.debug("Failed to get disk space", context: ["error": error.localizedDescription])
        }
        
        return 0.0
    }
    
    private func getOpenFileDescriptorCount() -> Int {
        // Simplified file descriptor count
        // In a real implementation, you would enumerate open file descriptors
        return 50 // Placeholder value
    }
    
    // MARK: - Scoring Functions
    
    private func calculateMemoryScore(usage: Double, percent: Double) -> Double {
        if percent > 90.0 {
            return 0.0
        } else if percent > 75.0 {
            return 0.5
        } else if percent > 50.0 {
            return 0.8
        } else {
            return 1.0
        }
    }
    
    private func calculateCPUScore(usage: Double) -> Double {
        if usage > 0.9 {
            return 0.0
        } else if usage > 0.75 {
            return 0.5
        } else if usage > 0.5 {
            return 0.8
        } else {
            return 1.0
        }
    }
    
    private func calculateLoadAverageScore(loadAverage: Double) -> Double {
        // Score based on system load relative to CPU cores
        let cpuCores = Double(ProcessInfo.processInfo.activeProcessorCount)
        let normalizedLoad = loadAverage / cpuCores
        
        if normalizedLoad > 2.0 {
            return 0.0
        } else if normalizedLoad > 1.0 {
            return 0.5
        } else if normalizedLoad > 0.5 {
            return 0.8
        } else {
            return 1.0
        }
    }
    
    private func calculateDiskSpaceScore(availableSpace: Double) -> Double {
        if availableSpace < 1.0 {
            return 0.0
        } else if availableSpace < 5.0 {
            return 0.5
        } else if availableSpace < 10.0 {
            return 0.8
        } else {
            return 1.0
        }
    }
    
    private func calculateFileDescriptorScore(openFDs: Int) -> Double {
        // Simplified scoring based on typical limits
        if openFDs > 1000 {
            return 0.0
        } else if openFDs > 500 {
            return 0.5
        } else if openFDs > 200 {
            return 0.8
        } else {
            return 1.0
        }
    }
}

// MARK: - Resource Data Structure

/// Internal resource data structure
private struct ResourceData {
    let memoryUsage: Double
    let totalMemory: UInt64
    let availableMemory: UInt64
    let cpuUsage: Double
    let loadAverage: Double
    let availableDiskSpace: Double
    let openFileDescriptors: Int
    
    init(
        memoryUsage: Double = 0.0,
        totalMemory: UInt64 = 0,
        availableMemory: UInt64 = 0,
        cpuUsage: Double = 0.0,
        loadAverage: Double = 0.0,
        availableDiskSpace: Double = 0.0,
        openFileDescriptors: Int = 0
    ) {
        self.memoryUsage = memoryUsage
        self.totalMemory = totalMemory
        self.availableMemory = availableMemory
        self.cpuUsage = cpuUsage
        self.loadAverage = loadAverage
        self.availableDiskSpace = availableDiskSpace
        self.openFileDescriptors = openFileDescriptors
    }
}