//
//  USBTransferPerformanceTests.swift
//  usbipd-mac
//
//  Performance validation tests for USB transfer latency and throughput
//  Tests concurrent request processing performance and resource usage
//

import XCTest
import Foundation
@testable import USBIPDCore
@testable import Common

/// Performance validation tests for USB transfer operations
/// Tests latency, throughput, concurrent processing, and resource utilization
/// Validates performance requirements and identifies bottlenecks
final class USBTransferPerformanceTests: XCTestCase {
    
    // MARK: - Test Properties
    
    var deviceDiscovery: IOKitDeviceDiscovery!
    var deviceCommunicator: USBDeviceCommunicator!
    var submitProcessor: USBSubmitProcessor!
    var unlinkProcessor: USBUnlinkProcessor!
    
    // Performance test configuration
    var testDevice: USBDevice?
    var performanceMetrics: PerformanceMetrics!
    
    // Test parameters
    static let performanceTestTimeout: TimeInterval = 60.0
    static let latencyTestIterations = 100
    static let throughputTestDurationSeconds = 10.0
    static let concurrentRequestCounts = [1, 5, 10, 25, 50]
    
    override func setUp() {
        super.setUp()
        
        deviceDiscovery = IOKitDeviceDiscovery()
        deviceCommunicator = USBDeviceCommunicator(deviceDiscovery: deviceDiscovery)
        submitProcessor = USBSubmitProcessor(deviceCommunicator: deviceCommunicator)
        unlinkProcessor = USBUnlinkProcessor(submitProcessor: submitProcessor)
        
        performanceMetrics = PerformanceMetrics()
        
        // Try to find a suitable test device
        do {
            let devices = try deviceDiscovery.discoverDevices()
            testDevice = devices.first
        } catch {
            // Performance tests will be skipped if no device available
        }
    }
    
    override func tearDown() {
        testDevice = nil
        performanceMetrics = nil
        
        deviceDiscovery?.stopNotifications()
        deviceDiscovery = nil
        deviceCommunicator = nil
        submitProcessor = nil
        unlinkProcessor = nil
        
        super.tearDown()
    }
    
    // MARK: - Latency Performance Tests
    
    func testControlTransferLatency() async throws {
        guard let device = testDevice else {
            throw XCTSkip("No USB device available for performance testing")
        }
        
        let expectation = XCTestExpectation(description: "Control transfer latency test")
        var latencies: [TimeInterval] = []
        
        // Warm up with a few requests
        for _ in 0..<5 {
            _ = try await performControlTransfer(device: device, seqnum: 0)
        }
        
        // Measure latency for multiple iterations
        for i in 0..<Self.latencyTestIterations {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            do {
                _ = try await performControlTransfer(device: device, seqnum: UInt32(i + 1))
                let endTime = CFAbsoluteTimeGetCurrent()
                let latency = (endTime - startTime) * 1000.0 // Convert to milliseconds
                latencies.append(latency)
            } catch {
                // Skip failed requests for performance measurement
                print("Skipping failed request \(i): \(error)")
            }
        }
        
        guard !latencies.isEmpty else {
            throw XCTSkip("No successful transfers for latency measurement")
        }
        
        // Calculate performance metrics
        let averageLatency = latencies.reduce(0, +) / Double(latencies.count)
        let minLatency = latencies.min() ?? 0
        let maxLatency = latencies.max() ?? 0
        let p95Latency = calculatePercentile(latencies.sorted(), percentile: 0.95)
        let p99Latency = calculatePercentile(latencies.sorted(), percentile: 0.99)
        
        // Log performance results
        print("Control Transfer Latency Performance:")
        print("  Successful transfers: \(latencies.count)/\(Self.latencyTestIterations)")
        print("  Average latency: \(String(format: "%.2f", averageLatency))ms")
        print("  Min latency: \(String(format: "%.2f", minLatency))ms")
        print("  Max latency: \(String(format: "%.2f", maxLatency))ms")
        print("  P95 latency: \(String(format: "%.2f", p95Latency))ms")
        print("  P99 latency: \(String(format: "%.2f", p99Latency))ms")
        
        // Performance assertions
        XCTAssertLessThan(averageLatency, 100.0, "Average control transfer latency should be under 100ms")
        XCTAssertLessThan(p95Latency, 200.0, "P95 latency should be under 200ms")
        XCTAssertLessThan(p99Latency, 500.0, "P99 latency should be under 500ms")
        
        // Record metrics
        performanceMetrics.recordLatency(
            transferType: "control",
            average: averageLatency,
            p95: p95Latency,
            p99: p99Latency
        )
    }
    
    func testBulkTransferLatency() async throws {
        guard let device = testDevice else {
            throw XCTSkip("No USB device available for performance testing")
        }
        
        var latencies: [TimeInterval] = []
        let transferSize: UInt32 = 1024 // 1KB transfers
        
        // Find a bulk endpoint (simplified - assumes endpoint 0x82 exists)
        let bulkEndpoint: UInt32 = 0x82
        
        for i in 0..<Self.latencyTestIterations {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            do {
                _ = try await performBulkTransfer(
                    device: device,
                    seqnum: UInt32(i + 1),
                    endpoint: bulkEndpoint,
                    transferSize: transferSize
                )
                let endTime = CFAbsoluteTimeGetCurrent()
                let latency = (endTime - startTime) * 1000.0
                latencies.append(latency)
            } catch {
                // Bulk transfers may fail on devices without bulk endpoints
                continue
            }
        }
        
        guard latencies.count > 10 else {
            throw XCTSkip("Insufficient successful bulk transfers for performance measurement")
        }
        
        let averageLatency = latencies.reduce(0, +) / Double(latencies.count)
        let p95Latency = calculatePercentile(latencies.sorted(), percentile: 0.95)
        
        print("Bulk Transfer Latency Performance:")
        print("  Transfer size: \(transferSize) bytes")
        print("  Successful transfers: \(latencies.count)/\(Self.latencyTestIterations)")
        print("  Average latency: \(String(format: "%.2f", averageLatency))ms")
        print("  P95 latency: \(String(format: "%.2f", p95Latency))ms")
        
        // Bulk transfers may have higher latency than control transfers
        XCTAssertLessThan(averageLatency, 250.0, "Average bulk transfer latency should be under 250ms")
        XCTAssertLessThan(p95Latency, 500.0, "P95 bulk latency should be under 500ms")
        
        performanceMetrics.recordLatency(
            transferType: "bulk",
            average: averageLatency,
            p95: p95Latency,
            p99: calculatePercentile(latencies.sorted(), percentile: 0.99)
        )
    }
    
    // MARK: - Throughput Performance Tests
    
    func testControlTransferThroughput() async throws {
        guard let device = testDevice else {
            throw XCTSkip("No USB device available for performance testing")
        }
        
        let testDuration = Self.throughputTestDurationSeconds
        let startTime = CFAbsoluteTimeGetCurrent()
        var completedTransfers = 0
        var seqnum: UInt32 = 1
        
        print("Starting control transfer throughput test for \(testDuration) seconds...")
        
        while (CFAbsoluteTimeGetCurrent() - startTime) < testDuration {
            do {
                _ = try await performControlTransfer(device: device, seqnum: seqnum)
                completedTransfers += 1
                seqnum += 1
            } catch {
                // Continue throughput test despite failures
                seqnum += 1
                continue
            }
        }
        
        let actualDuration = CFAbsoluteTimeGetCurrent() - startTime
        let transfersPerSecond = Double(completedTransfers) / actualDuration
        
        print("Control Transfer Throughput Performance:")
        print("  Test duration: \(String(format: "%.1f", actualDuration))s")
        print("  Completed transfers: \(completedTransfers)")
        print("  Throughput: \(String(format: "%.1f", transfersPerSecond)) transfers/sec")
        
        // Performance requirements
        XCTAssertGreaterThan(transfersPerSecond, 5.0, "Should achieve at least 5 control transfers per second")
        XCTAssertGreaterThan(completedTransfers, 10, "Should complete at least 10 transfers during test")
        
        performanceMetrics.recordThroughput(
            transferType: "control",
            transfersPerSecond: transfersPerSecond,
            bytesPerSecond: transfersPerSecond * 18 // Typical control transfer size
        )
    }
    
    func testBulkTransferThroughput() async throws {
        guard let device = testDevice else {
            throw XCTSkip("No USB device available for performance testing")
        }
        
        let transferSize: UInt32 = 4096 // 4KB transfers
        let testDuration = Self.throughputTestDurationSeconds
        let startTime = CFAbsoluteTimeGetCurrent()
        var completedTransfers = 0
        var totalBytesTransferred: UInt64 = 0
        var seqnum: UInt32 = 1
        
        print("Starting bulk transfer throughput test for \(testDuration) seconds...")
        
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
            throw XCTSkip("No successful bulk transfers for throughput measurement")
        }
        
        let actualDuration = CFAbsoluteTimeGetCurrent() - startTime
        let transfersPerSecond = Double(completedTransfers) / actualDuration
        let bytesPerSecond = Double(totalBytesTransferred) / actualDuration
        
        print("Bulk Transfer Throughput Performance:")
        print("  Transfer size: \(transferSize) bytes")
        print("  Test duration: \(String(format: "%.1f", actualDuration))s")
        print("  Completed transfers: \(completedTransfers)")
        print("  Total bytes: \(totalBytesTransferred)")
        print("  Throughput: \(String(format: "%.1f", transfersPerSecond)) transfers/sec")
        print("  Bandwidth: \(formatThroughput(bytesPerSecond))")
        
        XCTAssertGreaterThan(transfersPerSecond, 1.0, "Should achieve at least 1 bulk transfer per second")
        XCTAssertGreaterThan(bytesPerSecond, 1000.0, "Should achieve at least 1KB/s throughput")
        
        performanceMetrics.recordThroughput(
            transferType: "bulk",
            transfersPerSecond: transfersPerSecond,
            bytesPerSecond: bytesPerSecond
        )
    }
    
    // MARK: - Concurrent Processing Performance Tests
    
    func testConcurrentRequestProcessing() async throws {
        guard let device = testDevice else {
            throw XCTSkip("No USB device available for concurrent performance testing")
        }
        
        for concurrentCount in Self.concurrentRequestCounts {
            print("Testing concurrent processing with \(concurrentCount) requests...")
            
            let startTime = CFAbsoluteTimeGetCurrent()
            let expectation = XCTestExpectation(description: "Concurrent requests: \(concurrentCount)")
            expectation.expectedFulfillmentCount = concurrentCount
            
            var completedCount = 0
            var failedCount = 0
            
            // Launch concurrent requests
            for i in 0..<concurrentCount {
                Task {
                    do {
                        _ = try await performControlTransfer(device: device, seqnum: UInt32(i + 1))
                        completedCount += 1
                    } catch {
                        failedCount += 1
                    }
                    expectation.fulfill()
                }
            }
            
            // Wait for all requests to complete
            await fulfillment(of: [expectation], timeout: 30.0)
            
            let totalTime = CFAbsoluteTimeGetCurrent() - startTime
            let successRate = Double(completedCount) / Double(concurrentCount) * 100
            
            print("  Concurrent Requests: \(concurrentCount)")
            print("  Total Time: \(String(format: "%.2f", totalTime))s")
            print("  Completed: \(completedCount)")
            print("  Failed: \(failedCount)")
            print("  Success Rate: \(String(format: "%.1f", successRate))%")
            print("")
            
            // Performance assertions based on concurrency level
            if concurrentCount <= 10 {
                XCTAssertGreaterThan(successRate, 80.0, "Success rate should be >80% for \(concurrentCount) concurrent requests")
            } else {
                XCTAssertGreaterThan(successRate, 50.0, "Success rate should be >50% for \(concurrentCount) concurrent requests")
            }
            
            XCTAssertLessThan(totalTime, 15.0, "Concurrent processing should complete within 15 seconds")
            
            performanceMetrics.recordConcurrency(
                concurrentCount: concurrentCount,
                completedCount: completedCount,
                totalTime: totalTime,
                successRate: successRate
            )
        }
    }
    
    func testConcurrentRequestAndUnlinkOperations() async throws {
        guard let device = testDevice else {
            throw XCTSkip("No USB device available for concurrent unlink testing")
        }
        
        let requestCount = 20
        let unlinkCount = 5
        
        print("Testing concurrent requests with unlink operations...")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let expectation = XCTestExpectation(description: "Concurrent requests with unlinks")
        expectation.expectedFulfillmentCount = requestCount + unlinkCount
        
        var completedRequests = 0
        var cancelledRequests = 0
        var completedUnlinks = 0
        
        // Start submit requests
        for i in 0..<requestCount {
            Task {
                do {
                    _ = try await performControlTransfer(device: device, seqnum: UInt32(i + 1))
                    completedRequests += 1
                } catch {
                    if (error as? CancellationError) != nil {
                        cancelledRequests += 1
                    }
                }
                expectation.fulfill()
            }
        }
        
        // Start unlink requests after brief delay
        Task {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            for i in 0..<unlinkCount {
                Task {
                    do {
                        _ = try await performUnlinkRequest(
                            device: device,
                            seqnum: UInt32(requestCount + i + 1),
                            unlinkSeqnum: UInt32(i + 1)
                        )
                        completedUnlinks += 1
                    } catch {
                        // Unlink may fail if request already completed
                    }
                    expectation.fulfill()
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: 30.0)
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        
        print("Concurrent Request/Unlink Performance:")
        print("  Total requests: \(requestCount)")
        print("  Unlink attempts: \(unlinkCount)")
        print("  Completed requests: \(completedRequests)")
        print("  Cancelled requests: \(cancelledRequests)")
        print("  Completed unlinks: \(completedUnlinks)")
        print("  Total time: \(String(format: "%.2f", totalTime))s")
        
        // Verify system handled concurrent operations
        XCTAssertLessThan(totalTime, 20.0, "Concurrent operations should complete within 20 seconds")
        XCTAssertGreaterThan(completedRequests + cancelledRequests, requestCount / 2, "At least half the requests should be processed")
        
        performanceMetrics.recordUnlinkPerformance(
            totalRequests: requestCount,
            unlinkRequests: unlinkCount,
            completedUnlinks: completedUnlinks,
            totalTime: totalTime
        )
    }
    
    // MARK: - Resource Utilization Tests
    
    func testMemoryUsageUnderLoad() async throws {
        guard let device = testDevice else {
            throw XCTSkip("No USB device available for memory usage testing")
        }
        
        let initialMemory = getMemoryUsage()
        print("Initial memory usage: \(formatBytes(initialMemory))")
        
        // Generate sustained load
        let loadDuration = 5.0
        let startTime = CFAbsoluteTimeGetCurrent()
        var requestCount = 0
        
        while (CFAbsoluteTimeGetCurrent() - startTime) < loadDuration {
            // Generate multiple concurrent requests
            let batchSize = 10
            let expectation = XCTestExpectation(description: "Memory test batch")
            expectation.expectedFulfillmentCount = batchSize
            
            for i in 0..<batchSize {
                Task {
                    do {
                        _ = try await performControlTransfer(device: device, seqnum: UInt32(requestCount + i + 1))
                    } catch {
                        // Continue test despite failures
                    }
                    expectation.fulfill()
                }
            }
            
            await fulfillment(of: [expectation], timeout: 5.0)
            requestCount += batchSize
            
            // Brief pause between batches
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        let peakMemory = getMemoryUsage()
        let memoryIncrease = peakMemory - initialMemory
        
        print("Memory Usage Under Load:")
        print("  Initial memory: \(formatBytes(initialMemory))")
        print("  Peak memory: \(formatBytes(peakMemory))")
        print("  Memory increase: \(formatBytes(memoryIncrease))")
        print("  Total requests processed: \(requestCount)")
        
        // Memory usage assertions
        let maxAcceptableIncrease = 50 * 1024 * 1024 // 50MB
        XCTAssertLessThan(memoryIncrease, maxAcceptableIncrease, "Memory increase should be under 50MB")
        
        // Check for memory leaks by forcing cleanup and measuring again
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        let postCleanupMemory = getMemoryUsage()
        let potentialLeak = postCleanupMemory - initialMemory
        
        print("  Post-cleanup memory: \(formatBytes(postCleanupMemory))")
        print("  Potential leak: \(formatBytes(potentialLeak))")
        
        let maxAcceptableLeak = 10 * 1024 * 1024 // 10MB
        XCTAssertLessThan(potentialLeak, maxAcceptableLeak, "Potential memory leak should be under 10MB")
        
        performanceMetrics.recordMemoryUsage(
            initialMemory: initialMemory,
            peakMemory: peakMemory,
            finalMemory: postCleanupMemory
        )
    }
    
    // MARK: - Helper Methods
    
    private func performControlTransfer(device: USBDevice, seqnum: UInt32) async throws -> USBIPSubmitResponse {
        let setupPacket = Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00]) // GET_DESCRIPTOR
        let request = USBIPSubmitRequest(
            seqnum: seqnum,
            devid: UInt32(device.deviceID) ?? 0,
            direction: 1, // IN
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
            direction: 1, // IN
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
    
    private func performUnlinkRequest(
        device: USBDevice,
        seqnum: UInt32,
        unlinkSeqnum: UInt32
    ) async throws -> USBIPUnlinkResponse {
        let request = USBIPUnlinkRequest(
            seqnum: seqnum,
            devid: UInt32(device.deviceID) ?? 0,
            direction: 1,
            ep: 0x00,
            unlinkSeqnum: unlinkSeqnum
        )
        
        let requestData = try request.encode()
        let responseData = try await unlinkProcessor.processUnlinkRequest(requestData)
        return try USBIPUnlinkResponse.decode(from: responseData)
    }
    
    private func calculatePercentile(_ sortedValues: [TimeInterval], percentile: Double) -> Double {
        let index = Int(Double(sortedValues.count - 1) * percentile)
        return sortedValues[index]
    }
    
    private func getMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Int(info.resident_size)
        } else {
            return 0
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
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useBytes]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Performance Metrics Collection

class PerformanceMetrics {
    private var latencyMetrics: [String: LatencyMetric] = [:]
    private var throughputMetrics: [String: ThroughputMetric] = [:]
    private var concurrencyMetrics: [ConcurrencyMetric] = []
    private var unlinkMetrics: UnlinkMetric?
    private var memoryMetrics: MemoryMetric?
    
    struct LatencyMetric {
        let transferType: String
        let averageLatency: Double
        let p95Latency: Double
        let p99Latency: Double
    }
    
    struct ThroughputMetric {
        let transferType: String
        let transfersPerSecond: Double
        let bytesPerSecond: Double
    }
    
    struct ConcurrencyMetric {
        let concurrentCount: Int
        let completedCount: Int
        let totalTime: Double
        let successRate: Double
    }
    
    struct UnlinkMetric {
        let totalRequests: Int
        let unlinkRequests: Int
        let completedUnlinks: Int
        let totalTime: Double
    }
    
    struct MemoryMetric {
        let initialMemory: Int
        let peakMemory: Int
        let finalMemory: Int
    }
    
    func recordLatency(transferType: String, average: Double, p95: Double, p99: Double) {
        latencyMetrics[transferType] = LatencyMetric(
            transferType: transferType,
            averageLatency: average,
            p95Latency: p95,
            p99Latency: p99
        )
    }
    
    func recordThroughput(transferType: String, transfersPerSecond: Double, bytesPerSecond: Double) {
        throughputMetrics[transferType] = ThroughputMetric(
            transferType: transferType,
            transfersPerSecond: transfersPerSecond,
            bytesPerSecond: bytesPerSecond
        )
    }
    
    func recordConcurrency(concurrentCount: Int, completedCount: Int, totalTime: Double, successRate: Double) {
        concurrencyMetrics.append(ConcurrencyMetric(
            concurrentCount: concurrentCount,
            completedCount: completedCount,
            totalTime: totalTime,
            successRate: successRate
        ))
    }
    
    func recordUnlinkPerformance(totalRequests: Int, unlinkRequests: Int, completedUnlinks: Int, totalTime: Double) {
        unlinkMetrics = UnlinkMetric(
            totalRequests: totalRequests,
            unlinkRequests: unlinkRequests,
            completedUnlinks: completedUnlinks,
            totalTime: totalTime
        )
    }
    
    func recordMemoryUsage(initialMemory: Int, peakMemory: Int, finalMemory: Int) {
        memoryMetrics = MemoryMetric(
            initialMemory: initialMemory,
            peakMemory: peakMemory,
            finalMemory: finalMemory
        )
    }
    
    func generateReport() -> String {
        var report = "USB Transfer Performance Report\n"
        report += "=====================================\n\n"
        
        // Latency metrics
        if !latencyMetrics.isEmpty {
            report += "Latency Performance:\n"
            report += "-------------------\n"
            for (_, metric) in latencyMetrics {
                report += "\(metric.transferType.capitalized) Transfer:\n"
                report += "  Average: \(String(format: "%.2f", metric.averageLatency))ms\n"
                report += "  P95: \(String(format: "%.2f", metric.p95Latency))ms\n"
                report += "  P99: \(String(format: "%.2f", metric.p99Latency))ms\n"
            }
            report += "\n"
        }
        
        // Throughput metrics
        if !throughputMetrics.isEmpty {
            report += "Throughput Performance:\n"
            report += "----------------------\n"
            for (_, metric) in throughputMetrics {
                report += "\(metric.transferType.capitalized) Transfer:\n"
                report += "  Transfers/sec: \(String(format: "%.1f", metric.transfersPerSecond))\n"
                report += "  Bandwidth: \(formatThroughput(metric.bytesPerSecond))\n"
            }
            report += "\n"
        }
        
        // Concurrency metrics
        if !concurrencyMetrics.isEmpty {
            report += "Concurrency Performance:\n"
            report += "-----------------------\n"
            for metric in concurrencyMetrics {
                report += "Concurrent requests: \(metric.concurrentCount)\n"
                report += "  Success rate: \(String(format: "%.1f", metric.successRate))%\n"
                report += "  Time: \(String(format: "%.2f", metric.totalTime))s\n"
            }
            report += "\n"
        }
        
        return report
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