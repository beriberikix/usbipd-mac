// USBCommunicationPerformanceTests.swift
// Performance benchmarking and optimization validation for USB communication
// Validates performance objectives are met with real USB operations

import XCTest
import Foundation
@testable import USBIPDCore
@testable import USBIPDCLI
@testable import Common

#if canImport(SharedUtilities)
import SharedUtilities
#endif

/// Production performance tests for USB communication with strict latency requirements
/// Tests transfer latency measurement, throughput validation, and performance regression detection
/// Validates sub-50ms latency target and performance objectives for production deployment
final class USBCommunicationPerformanceTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol Implementation
    
    var environmentConfig: TestEnvironmentConfig {
        return TestEnvironmentConfig.production
    }
    
    var requiredCapabilities: TestEnvironmentCapabilities {
        return [.timeIntensiveOperations, .hardwareAccess, .networkAccess, .filesystemWrite]
    }
    
    var testCategory: String {
        return "performance"
    }
    
    // MARK: - Performance Constants
    
    // Primary performance targets
    static let targetAverageLatency: TimeInterval = 50.0    // 50ms target from requirements
    static let targetP95Latency: TimeInterval = 80.0       // P95 should be under 80ms 
    static let targetP99Latency: TimeInterval = 150.0      // P99 should be under 150ms
    
    // Throughput targets
    static let minControlTransfersPerSecond: Double = 20.0  // Minimum 20 control transfers/sec
    static let minBulkThroughputMBps: Double = 1.0          // Minimum 1 MB/s for bulk transfers
    
    // Test parameters
    static let latencyTestIterations = 200                  // More iterations for accurate measurement
    static let throughputTestDurationSeconds: TimeInterval = 15.0
    static let regressionTestIterations = 50
    static let performanceTestTimeout: TimeInterval = 300.0 // 5 minutes
    
    // MARK: - Test Properties
    
    private var logger: Logger!
    private var deviceDiscovery: DeviceDiscovery!
    private var deviceCommunicator: USBDeviceCommunicator!
    private var submitProcessor: USBSubmitProcessor!
    private var unlinkProcessor: USBUnlinkProcessor!
    private var systemExtensionManager: SystemExtensionManager!
    private var deviceClaimAdapter: SystemExtensionClaimAdapter!
    
    // Performance tracking
    private var performanceMetrics: ProductionPerformanceMetrics!
    private var baselineMetrics: BaselinePerformanceData?
    
    // Test device selection
    private var testDevices: [USBDevice] = []
    private var primaryTestDevice: USBDevice?
    
    // Synchronization
    private let performanceQueue = DispatchQueue(label: "performance-test-queue", qos: .userInitiated)
    
    // MARK: - Test Lifecycle
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        setUpTestSuite()
        
        // Skip if required capabilities not available
        if environmentConfig.shouldSkipTest(requiringCapabilities: requiredCapabilities) {
            throw XCTSkip("Performance tests require time-intensive operations and hardware access")
        }
        
        // Initialize logger
        logger = Logger(
            config: LoggerConfig(level: .info, includeTimestamp: true),
            subsystem: "com.usbipd.performance",
            category: "production-tests"
        )
        
        // Initialize core components
        if environmentConfig.hasCapability(.hardwareAccess) {
            deviceDiscovery = IOKitDeviceDiscovery()
        } else {
            let mockDiscovery = MockDeviceDiscovery()
            mockDiscovery.mockDevices = createPerformanceTestDevices()
            deviceDiscovery = mockDiscovery
        }
        
        // Initialize device communication stack
        deviceCommunicator = USBDeviceCommunicator(deviceDiscovery: deviceDiscovery)
        submitProcessor = USBSubmitProcessor(deviceCommunicator: deviceCommunicator)
        unlinkProcessor = USBUnlinkProcessor(submitProcessor: submitProcessor)
        
        // Initialize System Extension components
        systemExtensionManager = SystemExtensionManager()
        deviceClaimAdapter = SystemExtensionClaimAdapter(
            systemExtensionManager: systemExtensionManager
        )
        
        // Initialize performance tracking
        performanceMetrics = ProductionPerformanceMetrics()
        
        // Discover and validate test devices
        try setupTestDevices()
        
        // Load baseline performance data
        loadBaselineMetrics()
        
        logger.info("USB communication performance tests initialized", context: [
            "environment": environmentConfig.environment.rawValue,
            "testDeviceCount": testDevices.count,
            "hasBaseline": baselineMetrics != nil
        ])
    }
    
    override func tearDownWithError() throws {
        // Save performance metrics
        savePerformanceResults()
        
        // Clean shutdown
        try? systemExtensionManager?.stop()
        
        // Clean up test resources
        performanceMetrics = nil
        baselineMetrics = nil
        primaryTestDevice = nil
        testDevices.removeAll()
        
        systemExtensionManager = nil
        deviceClaimAdapter = nil
        submitProcessor = nil
        unlinkProcessor = nil
        deviceCommunicator = nil
        deviceDiscovery = nil
        logger = nil
        
        tearDownTestSuite()
        try super.tearDownWithError()
    }
    
    // MARK: - TestSuite Implementation
    
    func setUpTestSuite() {
        // Production test suite setup
    }
    
    func tearDownTestSuite() {
        // Production test suite cleanup
    }
    
    // MARK: - Core Latency Performance Tests
    
    func testControlTransferLatencyValidation() async throws {
        guard let device = primaryTestDevice else {
            throw XCTSkip("No suitable test device available for latency validation")
        }
        
        logger.info("Starting control transfer latency validation", context: [
            "device": "\(device.busID)-\(device.deviceID)",
            "iterations": Self.latencyTestIterations,
            "target": "\(Self.targetAverageLatency)ms"
        ])
        
        // Start System Extension for real USB operations
        try systemExtensionManager.start()
        defer { try? systemExtensionManager.stop() }
        
        // Claim device for testing
        let claimed = try deviceClaimAdapter.claimDevice(device)
        XCTAssertTrue(claimed, "Device must be claimed for performance testing")
        defer { try? deviceClaimAdapter.releaseDevice(device) }
        
        var latencies: [TimeInterval] = []
        var successCount = 0
        var errorCount = 0
        
        // Warm-up phase
        logger.info("Performing warm-up transfers")
        for i in 0..<10 {
            do {
                _ = try await performControlTransfer(device: device, seqnum: UInt32(i))
            } catch {
                // Ignore warm-up errors
            }
        }
        
        // Main latency measurement phase
        logger.info("Starting latency measurement phase")
        for i in 0..<Self.latencyTestIterations {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            do {
                _ = try await performControlTransfer(device: device, seqnum: UInt32(i + 100))
                let endTime = CFAbsoluteTimeGetCurrent()
                let latency = (endTime - startTime) * 1000.0 // Convert to milliseconds
                latencies.append(latency)
                successCount += 1
            } catch {
                errorCount += 1
                logger.debug("Transfer failed in iteration \(i)", context: [
                    "error": error.localizedDescription
                ])
            }
        }
        
        // Validate we have sufficient successful transfers for meaningful results
        let successRate = Double(successCount) / Double(Self.latencyTestIterations) * 100
        XCTAssertGreaterThan(successRate, 80.0, "Success rate must be >80% for valid performance measurement")
        XCTAssertGreaterThan(latencies.count, 50, "Need at least 50 successful transfers for valid statistics")
        
        // Calculate performance statistics
        let sortedLatencies = latencies.sorted()
        let averageLatency = latencies.reduce(0, +) / Double(latencies.count)
        let minLatency = sortedLatencies.first ?? 0
        let maxLatency = sortedLatencies.last ?? 0
        let medianLatency = calculatePercentile(sortedLatencies, percentile: 0.5)
        let p95Latency = calculatePercentile(sortedLatencies, percentile: 0.95)
        let p99Latency = calculatePercentile(sortedLatencies, percentile: 0.99)
        let stdDeviation = calculateStandardDeviation(latencies, mean: averageLatency)
        
        // Log detailed performance results
        logger.info("Control transfer latency performance results", context: [
            "device": "\(device.busID)-\(device.deviceID)",
            "iterations": Self.latencyTestIterations,
            "successCount": successCount,
            "errorCount": errorCount,
            "successRate": String(format: "%.1f%%", successRate),
            "averageLatency": String(format: "%.2fms", averageLatency),
            "minLatency": String(format: "%.2fms", minLatency),
            "maxLatency": String(format: "%.2fms", maxLatency),
            "medianLatency": String(format: "%.2fms", medianLatency),
            "p95Latency": String(format: "%.2fms", p95Latency),
            "p99Latency": String(format: "%.2fms", p99Latency),
            "stdDeviation": String(format: "%.2fms", stdDeviation)
        ])
        
        // CRITICAL: Validate against performance targets
        XCTAssertLessThan(averageLatency, Self.targetAverageLatency,
                         "PERFORMANCE REGRESSION: Average latency \(String(format: "%.2f", averageLatency))ms exceeds target \(Self.targetAverageLatency)ms")
        
        XCTAssertLessThan(p95Latency, Self.targetP95Latency,
                         "PERFORMANCE REGRESSION: P95 latency \(String(format: "%.2f", p95Latency))ms exceeds target \(Self.targetP95Latency)ms")
        
        XCTAssertLessThan(p99Latency, Self.targetP99Latency,
                         "PERFORMANCE REGRESSION: P99 latency \(String(format: "%.2f", p99Latency))ms exceeds target \(Self.targetP99Latency)ms")
        
        // Record metrics for regression analysis
        performanceMetrics.recordLatencyResults(
            transferType: "control",
            averageLatency: averageLatency,
            p95Latency: p95Latency,
            p99Latency: p99Latency,
            stdDeviation: stdDeviation,
            successRate: successRate,
            iterations: Self.latencyTestIterations
        )
        
        // Compare against baseline if available
        if let baseline = baselineMetrics?.controlTransferLatency {
            analyzePerformanceRegression(
                testName: "control_transfer_latency",
                currentValue: averageLatency,
                baselineValue: baseline.averageLatency,
                tolerance: baseline.averageLatency * 0.1 // 10% tolerance
            )
        }
    }
    
    func testBulkTransferLatencyValidation() async throws {
        guard let device = primaryTestDevice else {
            throw XCTSkip("No suitable test device available for bulk latency validation")
        }
        
        logger.info("Starting bulk transfer latency validation", context: [
            "device": "\(device.busID)-\(device.deviceID)",
            "transferSize": "4KB"
        ])
        
        try systemExtensionManager.start()
        defer { try? systemExtensionManager.stop() }
        
        let claimed = try deviceClaimAdapter.claimDevice(device)
        XCTAssertTrue(claimed, "Device must be claimed for bulk transfer testing")
        defer { try? deviceClaimAdapter.releaseDevice(device) }
        
        var latencies: [TimeInterval] = []
        let transferSize: UInt32 = 4096 // 4KB transfers
        let bulkEndpoint: UInt32 = 0x82 // Typical bulk IN endpoint
        
        // Test bulk transfer latency
        for i in 0..<Self.regressionTestIterations {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            do {
                _ = try await performBulkTransfer(
                    device: device,
                    seqnum: UInt32(i + 200),
                    endpoint: bulkEndpoint,
                    transferSize: transferSize
                )
                let endTime = CFAbsoluteTimeGetCurrent()
                let latency = (endTime - startTime) * 1000.0
                latencies.append(latency)
            } catch {
                // Some devices may not support bulk transfers - continue testing
                continue
            }
        }
        
        guard latencies.count >= 10 else {
            throw XCTSkip("Insufficient successful bulk transfers - device may not support bulk endpoints")
        }
        
        let averageLatency = latencies.reduce(0, +) / Double(latencies.count)
        let p95Latency = calculatePercentile(latencies.sorted(), percentile: 0.95)
        
        logger.info("Bulk transfer latency results", context: [
            "transferSize": transferSize,
            "successfulTransfers": latencies.count,
            "averageLatency": String(format: "%.2fms", averageLatency),
            "p95Latency": String(format: "%.2fms", p95Latency)
        ])
        
        // Bulk transfers typically have higher latency tolerance
        let bulkLatencyTarget = Self.targetAverageLatency * 2.0 // 100ms for bulk
        XCTAssertLessThan(averageLatency, bulkLatencyTarget,
                         "Bulk transfer average latency should be under \(bulkLatencyTarget)ms")
        
        performanceMetrics.recordLatencyResults(
            transferType: "bulk",
            averageLatency: averageLatency,
            p95Latency: p95Latency,
            p99Latency: calculatePercentile(latencies.sorted(), percentile: 0.99),
            stdDeviation: calculateStandardDeviation(latencies, mean: averageLatency),
            successRate: Double(latencies.count) / Double(Self.regressionTestIterations) * 100,
            iterations: Self.regressionTestIterations
        )
    }
    
    // MARK: - Throughput Performance Tests
    
    func testControlTransferThroughputValidation() async throws {
        guard let device = primaryTestDevice else {
            throw XCTSkip("No suitable test device for throughput validation")
        }
        
        logger.info("Starting control transfer throughput validation", context: [
            "device": "\(device.busID)-\(device.deviceID)",
            "duration": "\(Self.throughputTestDurationSeconds)s",
            "target": "\(Self.minControlTransfersPerSecond) transfers/sec"
        ])
        
        try systemExtensionManager.start()
        defer { try? systemExtensionManager.stop() }
        
        let claimed = try deviceClaimAdapter.claimDevice(device)
        XCTAssertTrue(claimed, "Device must be claimed for throughput testing")
        defer { try? deviceClaimAdapter.releaseDevice(device) }
        
        let testDuration = Self.throughputTestDurationSeconds
        let startTime = CFAbsoluteTimeGetCurrent()
        var completedTransfers = 0
        var totalBytes: UInt64 = 0
        var seqnum: UInt32 = 300
        
        logger.info("Starting throughput measurement phase")
        
        while (CFAbsoluteTimeGetCurrent() - startTime) < testDuration {
            do {
                let response = try await performControlTransfer(device: device, seqnum: seqnum)
                completedTransfers += 1
                totalBytes += UInt64(response.actualLength)
                seqnum += 1
            } catch {
                seqnum += 1
                // Continue throughput test despite individual failures
            }
        }
        
        let actualDuration = CFAbsoluteTimeGetCurrent() - startTime
        let transfersPerSecond = Double(completedTransfers) / actualDuration
        let bytesPerSecond = Double(totalBytes) / actualDuration
        let mbPerSecond = bytesPerSecond / (1024 * 1024)
        
        logger.info("Control transfer throughput results", context: [
            "testDuration": String(format: "%.1fs", actualDuration),
            "completedTransfers": completedTransfers,
            "totalBytes": totalBytes,
            "transfersPerSecond": String(format: "%.1f", transfersPerSecond),
            "mbPerSecond": String(format: "%.3f", mbPerSecond)
        ])
        
        // Validate throughput targets
        XCTAssertGreaterThan(transfersPerSecond, Self.minControlTransfersPerSecond,
                            "PERFORMANCE REGRESSION: Throughput \(String(format: "%.1f", transfersPerSecond)) transfers/sec below target \(Self.minControlTransfersPerSecond)")
        
        XCTAssertGreaterThan(completedTransfers, 20,
                            "Should complete at least 20 transfers during \(testDuration)s test")
        
        performanceMetrics.recordThroughputResults(
            transferType: "control",
            transfersPerSecond: transfersPerSecond,
            bytesPerSecond: bytesPerSecond,
            testDuration: actualDuration,
            totalTransfers: completedTransfers
        )
        
        // Compare against baseline throughput
        if let baseline = baselineMetrics?.controlTransferThroughput {
            analyzePerformanceRegression(
                testName: "control_transfer_throughput",
                currentValue: transfersPerSecond,
                baselineValue: baseline.transfersPerSecond,
                tolerance: baseline.transfersPerSecond * 0.2 // 20% tolerance for throughput
            )
        }
    }
    
    func testBulkTransferThroughputValidation() async throws {
        guard let device = primaryTestDevice else {
            throw XCTSkip("No suitable test device for bulk throughput validation")
        }
        
        logger.info("Starting bulk transfer throughput validation")
        
        try systemExtensionManager.start()
        defer { try? systemExtensionManager.stop() }
        
        let claimed = try deviceClaimAdapter.claimDevice(device)
        XCTAssertTrue(claimed, "Device must be claimed for bulk throughput testing")
        defer { try? deviceClaimAdapter.releaseDevice(device) }
        
        let transferSize: UInt32 = 8192 // 8KB transfers for better throughput
        let testDuration = Self.throughputTestDurationSeconds
        let startTime = CFAbsoluteTimeGetCurrent()
        var completedTransfers = 0
        var totalBytesTransferred: UInt64 = 0
        var seqnum: UInt32 = 400
        
        while (CFAbsoluteTimeGetCurrent() - startTime) < testDuration {
            do {
                let response = try await performBulkTransfer(
                    device: device,
                    seqnum: seqnum,
                    endpoint: 0x82,
                    transferSize: transferSize
                )
                completedTransfers += 1
                totalBytesTransferred += UInt64(response.actualLength)
                seqnum += 1
            } catch {
                seqnum += 1
                continue
            }
        }
        
        guard completedTransfers > 0 else {
            throw XCTSkip("No successful bulk transfers - device may not support bulk endpoints")
        }
        
        let actualDuration = CFAbsoluteTimeGetCurrent() - startTime
        let transfersPerSecond = Double(completedTransfers) / actualDuration
        let bytesPerSecond = Double(totalBytesTransferred) / actualDuration
        let mbPerSecond = bytesPerSecond / (1024 * 1024)
        
        logger.info("Bulk transfer throughput results", context: [
            "transferSize": transferSize,
            "completedTransfers": completedTransfers,
            "totalBytes": totalBytesTransferred,
            "transfersPerSecond": String(format: "%.1f", transfersPerSecond),
            "mbPerSecond": String(format: "%.3f", mbPerSecond)
        ])
        
        // Validate bulk throughput targets
        XCTAssertGreaterThan(mbPerSecond, Self.minBulkThroughputMBps,
                            "PERFORMANCE REGRESSION: Bulk throughput \(String(format: "%.3f", mbPerSecond)) MB/s below target \(Self.minBulkThroughputMBps)")
        
        performanceMetrics.recordThroughputResults(
            transferType: "bulk",
            transfersPerSecond: transfersPerSecond,
            bytesPerSecond: bytesPerSecond,
            testDuration: actualDuration,
            totalTransfers: completedTransfers
        )
    }
    
    // MARK: - Performance Regression Testing
    
    func testPerformanceRegressionValidation() async throws {
        guard let device = primaryTestDevice,
              let baseline = baselineMetrics else {
            throw XCTSkip("Performance regression testing requires baseline metrics and test device")
        }
        
        logger.info("Starting performance regression validation", context: [
            "device": "\(device.busID)-\(device.deviceID)",
            "baselineDate": baseline.recordedDate
        ])
        
        try systemExtensionManager.start()
        defer { try? systemExtensionManager.stop() }
        
        let claimed = try deviceClaimAdapter.claimDevice(device)
        XCTAssertTrue(claimed, "Device must be claimed for regression testing")
        defer { try? deviceClaimAdapter.releaseDevice(device) }
        
        // Quick regression test with fewer iterations
        var latencies: [TimeInterval] = []
        
        for i in 0..<Self.regressionTestIterations {
            let startTime = CFAbsoluteTimeGetCurrent()
            do {
                _ = try await performControlTransfer(device: device, seqnum: UInt32(i + 500))
                let endTime = CFAbsoluteTimeGetCurrent()
                let latency = (endTime - startTime) * 1000.0
                latencies.append(latency)
            } catch {
                continue
            }
        }
        
        guard latencies.count >= 20 else {
            throw XCTSkip("Insufficient successful transfers for regression analysis")
        }
        
        let currentAvgLatency = latencies.reduce(0, +) / Double(latencies.count)
        let baselineAvgLatency = baseline.controlTransferLatency.averageLatency
        
        // Calculate performance change
        let performanceChange = ((currentAvgLatency - baselineAvgLatency) / baselineAvgLatency) * 100
        let isRegression = performanceChange > 15.0 // 15% regression threshold
        
        logger.info("Performance regression analysis", context: [
            "currentLatency": String(format: "%.2fms", currentAvgLatency),
            "baselineLatency": String(format: "%.2fms", baselineAvgLatency),
            "performanceChange": String(format: "%.1f%%", performanceChange),
            "isRegression": isRegression
        ])
        
        // CRITICAL: Fail if significant performance regression detected
        XCTAssertFalse(isRegression,
                      "PERFORMANCE REGRESSION DETECTED: Latency increased by \(String(format: "%.1f", performanceChange))% from baseline")
        
        XCTAssertLessThan(currentAvgLatency, Self.targetAverageLatency,
                         "Current latency \(String(format: "%.2f", currentAvgLatency))ms exceeds target \(Self.targetAverageLatency)ms")
        
        // Record regression test results
        performanceMetrics.recordRegressionTest(
            testName: "control_transfer_regression",
            currentValue: currentAvgLatency,
            baselineValue: baselineAvgLatency,
            changePercent: performanceChange,
            isPassing: !isRegression
        )
    }
    
    func testConcurrentPerformanceValidation() async throws {
        guard let device = primaryTestDevice else {
            throw XCTSkip("No suitable test device for concurrent performance validation")
        }
        
        logger.info("Starting concurrent performance validation")
        
        try systemExtensionManager.start()
        defer { try? systemExtensionManager.stop() }
        
        let claimed = try deviceClaimAdapter.claimDevice(device)
        XCTAssertTrue(claimed, "Device must be claimed for concurrent testing")
        defer { try? deviceClaimAdapter.releaseDevice(device) }
        
        let concurrentRequests = [5, 10, 15] // Different concurrency levels
        
        for concurrentCount in concurrentRequests {
            logger.info("Testing concurrent performance", context: [
                "concurrentRequests": concurrentCount
            ])
            
            let startTime = CFAbsoluteTimeGetCurrent()
            let expectation = XCTestExpectation(description: "Concurrent performance: \(concurrentCount)")
            expectation.expectedFulfillmentCount = concurrentCount
            
            var completedCount = 0
            var totalLatency: TimeInterval = 0
            let syncQueue = DispatchQueue(label: "concurrent-sync")
            
            // Launch concurrent requests
            for i in 0..<concurrentCount {
                Task {
                    let requestStartTime = CFAbsoluteTimeGetCurrent()
                    do {
                        _ = try await performControlTransfer(device: device, seqnum: UInt32(600 + i))
                        let requestEndTime = CFAbsoluteTimeGetCurrent()
                        let requestLatency = (requestEndTime - requestStartTime) * 1000.0
                        
                        syncQueue.sync {
                            completedCount += 1
                            totalLatency += requestLatency
                        }
                    } catch {
                        // Track failures but continue test
                    }
                    expectation.fulfill()
                }
            }
            
            // Wait for completion
            await fulfillment(of: [expectation], timeout: 30.0)
            
            let totalTime = CFAbsoluteTimeGetCurrent() - startTime
            let successRate = Double(completedCount) / Double(concurrentCount) * 100
            let averageLatency = completedCount > 0 ? totalLatency / Double(completedCount) : 0
            
            logger.info("Concurrent performance results", context: [
                "concurrentRequests": concurrentCount,
                "completedRequests": completedCount,
                "successRate": String(format: "%.1f%%", successRate),
                "totalTime": String(format: "%.2fs", totalTime),
                "averageLatency": String(format: "%.2fms", averageLatency)
            ])
            
            // Performance assertions for concurrent operations
            XCTAssertGreaterThan(successRate, 70.0, "Success rate should be >70% for \(concurrentCount) concurrent requests")
            
            if completedCount > 0 {
                XCTAssertLessThan(averageLatency, Self.targetAverageLatency * 1.5,
                                 "Concurrent latency should be within 1.5x of target even under load")
            }
            
            performanceMetrics.recordConcurrentPerformance(
                concurrentCount: concurrentCount,
                completedCount: completedCount,
                totalTime: totalTime,
                averageLatency: averageLatency,
                successRate: successRate
            )
        }
    }
    
    // MARK: - Resource Usage and Optimization Tests
    
    func testMemoryPerformanceUnderLoad() async throws {
        guard let device = primaryTestDevice else {
            throw XCTSkip("No suitable test device for memory performance testing")
        }
        
        logger.info("Starting memory performance validation under load")
        
        try systemExtensionManager.start()
        defer { try? systemExtensionManager.stop() }
        
        let claimed = try deviceClaimAdapter.claimDevice(device)
        XCTAssertTrue(claimed, "Device must be claimed for memory testing")
        defer { try? deviceClaimAdapter.releaseDevice(device) }
        
        let initialMemory = getCurrentMemoryUsage()
        logger.info("Initial memory usage", context: [
            "memoryMB": String(format: "%.1f", Double(initialMemory) / (1024 * 1024))
        ])
        
        // Generate sustained load for memory testing
        let loadDuration: TimeInterval = 10.0
        let startTime = CFAbsoluteTimeGetCurrent()
        var requestCount = 0
        var peakMemory = initialMemory
        
        while (CFAbsoluteTimeGetCurrent() - startTime) < loadDuration {
            // Generate batch of requests
            let batchSize = 15
            let expectation = XCTestExpectation(description: "Memory test batch")
            expectation.expectedFulfillmentCount = batchSize
            
            for i in 0..<batchSize {
                Task {
                    do {
                        _ = try await performControlTransfer(device: device, seqnum: UInt32(700 + requestCount + i))
                    } catch {
                        // Continue memory test despite transfer failures
                    }
                    expectation.fulfill()
                }
            }
            
            await fulfillment(of: [expectation], timeout: 5.0)
            requestCount += batchSize
            
            // Check memory usage
            let currentMemory = getCurrentMemoryUsage()
            peakMemory = max(peakMemory, currentMemory)
            
            // Brief pause between batches
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }
        
        // Allow time for cleanup
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        let finalMemory = getCurrentMemoryUsage()
        
        let memoryIncrease = peakMemory - initialMemory
        let memoryLeak = finalMemory - initialMemory
        
        logger.info("Memory performance results", context: [
            "initialMemoryMB": String(format: "%.1f", Double(initialMemory) / (1024 * 1024)),
            "peakMemoryMB": String(format: "%.1f", Double(peakMemory) / (1024 * 1024)),
            "finalMemoryMB": String(format: "%.1f", Double(finalMemory) / (1024 * 1024)),
            "memoryIncreaseMB": String(format: "%.1f", Double(memoryIncrease) / (1024 * 1024)),
            "potentialLeakMB": String(format: "%.1f", Double(memoryLeak) / (1024 * 1024)),
            "requestsProcessed": requestCount
        ])
        
        // Memory usage assertions
        let maxAcceptableIncrease = 100 * 1024 * 1024 // 100MB
        let maxAcceptableLeak = 20 * 1024 * 1024      // 20MB
        
        XCTAssertLessThan(memoryIncrease, maxAcceptableIncrease,
                         "Memory increase \(formatBytes(memoryIncrease)) should be under 100MB")
        
        XCTAssertLessThan(memoryLeak, maxAcceptableLeak,
                         "Potential memory leak \(formatBytes(memoryLeak)) should be under 20MB")
        
        performanceMetrics.recordMemoryUsage(
            initialMemory: initialMemory,
            peakMemory: peakMemory,
            finalMemory: finalMemory,
            requestsProcessed: requestCount
        )
    }
    
    // MARK: - Helper Methods
    
    private func setupTestDevices() throws {
        testDevices = try deviceDiscovery.discoverDevices()
        
        guard !testDevices.isEmpty else {
            throw XCTSkip("No USB devices available for performance testing")
        }
        
        // Select best device for testing (prefer HID devices for reliability)
        primaryTestDevice = testDevices.first { device in
            device.deviceClass == 3 // HID devices are generally more reliable for testing
        } ?? testDevices.first
        
        logger.info("Performance test devices selected", context: [
            "totalDevices": testDevices.count,
            "primaryDevice": primaryTestDevice.map { "\($0.busID)-\($0.deviceID)" } ?? "none"
        ])
    }
    
    private func createPerformanceTestDevices() -> [USBDevice] {
        // Create optimized mock devices for performance testing
        return [
            USBDevice(
                busID: "1",
                deviceID: "1",
                vendorID: 0x05AC,
                productID: 0x030D,
                deviceClass: 3,    // HID
                deviceSubClass: 1,
                deviceProtocol: 2,
                speed: .high,
                manufacturerString: "Performance Test",
                productString: "Test Device 1",
                serialNumberString: "PERF001"
            ),
            USBDevice(
                busID: "1",
                deviceID: "2",
                vendorID: 0x0781,
                productID: 0x5567,
                deviceClass: 8,    // Mass Storage
                deviceSubClass: 6,
                deviceProtocol: 80,
                speed: .superSpeed,
                manufacturerString: "Performance Test",
                productString: "Test Device 2",
                serialNumberString: "PERF002"
            )
        ]
    }
    
    private func performControlTransfer(device: USBDevice, seqnum: UInt32) async throws -> USBIPSubmitResponse {
        let setupPacket = Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00]) // GET_DESCRIPTOR
        let request = USBIPSubmitRequest(
            seqnum: seqnum,
            devid: UInt32(device.deviceID) ?? 0,
            direction: 1,
            ep: 0x00,
            transferFlags: 0,
            transferBufferLength: 18,
            startFrame: 0,
            numberOfPackets: 0,
            interval: 0,
            setup: setupPacket,
            transferBuffer: nil
        )
        
        let requestData = try request.encode()
        let responseData = try await submitProcessor.processSubmitRequest(requestData)
        return try USBIPSubmitResponse.decode(from: responseData)
    }
    
    private func performBulkTransfer(
        device: USBDevice,
        seqnum: UInt32,
        endpoint: UInt32,
        transferSize: UInt32
    ) async throws -> USBIPSubmitResponse {
        let request = USBIPSubmitRequest(
            seqnum: seqnum,
            devid: UInt32(device.deviceID) ?? 0,
            direction: 1,
            ep: endpoint,
            transferFlags: 0,
            transferBufferLength: transferSize,
            startFrame: 0,
            numberOfPackets: 0,
            interval: 0,
            setup: Data(count: 8),
            transferBuffer: nil
        )
        
        let requestData = try request.encode()
        let responseData = try await submitProcessor.processSubmitRequest(requestData)
        return try USBIPSubmitResponse.decode(from: responseData)
    }
    
    private func calculatePercentile(_ sortedValues: [TimeInterval], percentile: Double) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        let index = min(Int(Double(sortedValues.count - 1) * percentile), sortedValues.count - 1)
        return sortedValues[index]
    }
    
    private func calculateStandardDeviation(_ values: [TimeInterval], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let variance = values.reduce(0) { sum, value in
            sum + pow(value - mean, 2)
        } / Double(values.count - 1)
        return sqrt(variance)
    }
    
    private func getCurrentMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useBytes]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func analyzePerformanceRegression(testName: String, currentValue: Double, baselineValue: Double, tolerance: Double) {
        let change = currentValue - baselineValue
        let percentChange = (change / baselineValue) * 100
        let isRegression = change > tolerance
        
        logger.info("Performance regression analysis", context: [
            "test": testName,
            "currentValue": String(format: "%.3f", currentValue),
            "baselineValue": String(format: "%.3f", baselineValue),
            "change": String(format: "%.3f", change),
            "percentChange": String(format: "%.1f%%", percentChange),
            "tolerance": String(format: "%.3f", tolerance),
            "isRegression": isRegression
        ])
        
        if isRegression {
            logger.error("Performance regression detected", context: [
                "test": testName,
                "regressionPercent": String(format: "%.1f%%", percentChange)
            ])
        }
    }
    
    private func loadBaselineMetrics() {
        // Load baseline performance data from previous runs
        // This would typically be loaded from a configuration file or database
        baselineMetrics = BaselinePerformanceData(
            recordedDate: "2024-01-01",
            controlTransferLatency: BaselineLatencyData(
                averageLatency: 45.0,
                p95Latency: 75.0,
                p99Latency: 120.0
            ),
            controlTransferThroughput: BaseThroughputData(
                transfersPerSecond: 25.0,
                bytesPerSecond: 500.0
            )
        )
    }
    
    private func savePerformanceResults() {
        // Save performance metrics for future baseline comparison
        let report = performanceMetrics.generateDetailedReport()
        logger.info("Performance test results", context: [
            "report": report
        ])
    }
}

// MARK: - Performance Metrics Collection

class ProductionPerformanceMetrics {
    private var latencyResults: [String: LatencyResult] = [:]
    private var throughputResults: [String: ThroughputResult] = [:]
    private var regressionTests: [RegressionTestResult] = []
    private var concurrentResults: [ConcurrentPerformanceResult] = []
    private var memoryResults: [MemoryUsageResult] = []
    
    struct LatencyResult {
        let transferType: String
        let averageLatency: Double
        let p95Latency: Double
        let p99Latency: Double
        let stdDeviation: Double
        let successRate: Double
        let iterations: Int
        let timestamp: Date
    }
    
    struct ThroughputResult {
        let transferType: String
        let transfersPerSecond: Double
        let bytesPerSecond: Double
        let testDuration: TimeInterval
        let totalTransfers: Int
        let timestamp: Date
    }
    
    struct RegressionTestResult {
        let testName: String
        let currentValue: Double
        let baselineValue: Double
        let changePercent: Double
        let isPassing: Bool
        let timestamp: Date
    }
    
    struct ConcurrentPerformanceResult {
        let concurrentCount: Int
        let completedCount: Int
        let totalTime: TimeInterval
        let averageLatency: Double
        let successRate: Double
        let timestamp: Date
    }
    
    struct MemoryUsageResult {
        let initialMemory: Int
        let peakMemory: Int
        let finalMemory: Int
        let requestsProcessed: Int
        let timestamp: Date
    }
    
    func recordLatencyResults(
        transferType: String,
        averageLatency: Double,
        p95Latency: Double,
        p99Latency: Double,
        stdDeviation: Double,
        successRate: Double,
        iterations: Int
    ) {
        latencyResults[transferType] = LatencyResult(
            transferType: transferType,
            averageLatency: averageLatency,
            p95Latency: p95Latency,
            p99Latency: p99Latency,
            stdDeviation: stdDeviation,
            successRate: successRate,
            iterations: iterations,
            timestamp: Date()
        )
    }
    
    func recordThroughputResults(
        transferType: String,
        transfersPerSecond: Double,
        bytesPerSecond: Double,
        testDuration: TimeInterval,
        totalTransfers: Int
    ) {
        throughputResults[transferType] = ThroughputResult(
            transferType: transferType,
            transfersPerSecond: transfersPerSecond,
            bytesPerSecond: bytesPerSecond,
            testDuration: testDuration,
            totalTransfers: totalTransfers,
            timestamp: Date()
        )
    }
    
    func recordRegressionTest(
        testName: String,
        currentValue: Double,
        baselineValue: Double,
        changePercent: Double,
        isPassing: Bool
    ) {
        regressionTests.append(RegressionTestResult(
            testName: testName,
            currentValue: currentValue,
            baselineValue: baselineValue,
            changePercent: changePercent,
            isPassing: isPassing,
            timestamp: Date()
        ))
    }
    
    func recordConcurrentPerformance(
        concurrentCount: Int,
        completedCount: Int,
        totalTime: TimeInterval,
        averageLatency: Double,
        successRate: Double
    ) {
        concurrentResults.append(ConcurrentPerformanceResult(
            concurrentCount: concurrentCount,
            completedCount: completedCount,
            totalTime: totalTime,
            averageLatency: averageLatency,
            successRate: successRate,
            timestamp: Date()
        ))
    }
    
    func recordMemoryUsage(
        initialMemory: Int,
        peakMemory: Int,
        finalMemory: Int,
        requestsProcessed: Int
    ) {
        memoryResults.append(MemoryUsageResult(
            initialMemory: initialMemory,
            peakMemory: peakMemory,
            finalMemory: finalMemory,
            requestsProcessed: requestsProcessed,
            timestamp: Date()
        ))
    }
    
    func generateDetailedReport() -> String {
        var report = "USB Communication Performance Test Results\n"
        report += "==========================================\n\n"
        
        // Latency results
        if !latencyResults.isEmpty {
            report += "Latency Performance:\n"
            report += "-------------------\n"
            for (_, result) in latencyResults {
                report += "\(result.transferType.capitalized) Transfer Latency:\n"
                report += "  Average: \(String(format: "%.2f", result.averageLatency))ms\n"
                report += "  P95: \(String(format: "%.2f", result.p95Latency))ms\n"
                report += "  P99: \(String(format: "%.2f", result.p99Latency))ms\n"
                report += "  Std Dev: \(String(format: "%.2f", result.stdDeviation))ms\n"
                report += "  Success Rate: \(String(format: "%.1f", result.successRate))%\n"
                report += "  Iterations: \(result.iterations)\n\n"
            }
        }
        
        // Throughput results
        if !throughputResults.isEmpty {
            report += "Throughput Performance:\n"
            report += "----------------------\n"
            for (_, result) in throughputResults {
                report += "\(result.transferType.capitalized) Transfer Throughput:\n"
                report += "  Transfers/sec: \(String(format: "%.1f", result.transfersPerSecond))\n"
                report += "  MB/s: \(String(format: "%.3f", result.bytesPerSecond / (1024 * 1024)))\n"
                report += "  Duration: \(String(format: "%.1f", result.testDuration))s\n"
                report += "  Total Transfers: \(result.totalTransfers)\n\n"
            }
        }
        
        // Regression test results
        if !regressionTests.isEmpty {
            report += "Regression Test Results:\n"
            report += "-----------------------\n"
            for result in regressionTests {
                let status = result.isPassing ? "PASS" : "FAIL"
                report += "\(result.testName): \(status)\n"
                report += "  Current: \(String(format: "%.3f", result.currentValue))\n"
                report += "  Baseline: \(String(format: "%.3f", result.baselineValue))\n"
                report += "  Change: \(String(format: "%.1f", result.changePercent))%\n\n"
            }
        }
        
        return report
    }
}

// MARK: - Baseline Performance Data

struct BaselinePerformanceData {
    let recordedDate: String
    let controlTransferLatency: BaselineLatencyData
    let controlTransferThroughput: BaseThroughputData
}

struct BaselineLatencyData {
    let averageLatency: Double
    let p95Latency: Double
    let p99Latency: Double
}

struct BaseThroughputData {
    let transfersPerSecond: Double
    let bytesPerSecond: Double
}

// MARK: - Mock Device Discovery for Performance Testing

private class MockDeviceDiscovery: DeviceDiscovery {
    var mockDevices: [USBDevice] = []
    
    func discoverDevices() throws -> [USBDevice] {
        return mockDevices
    }
    
    func getDevice(busID: String, deviceID: String) throws -> USBDevice? {
        return mockDevices.first { $0.busID == busID && $0.deviceID == deviceID }
    }
    
    func getDeviceByIdentifier(_ identifier: String) throws -> USBDevice? {
        let components = identifier.split(separator: "-")
        guard components.count >= 2 else { return nil }
        return try getDevice(busID: String(components[0]), deviceID: String(components[1]))
    }
    
    func startNotifications() throws {
        // Mock implementation
    }
    
    func stopNotifications() {
        // Mock implementation
    }
}