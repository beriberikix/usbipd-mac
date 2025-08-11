import XCTest
import Foundation
import IOKit
@testable import USBIPDCore
@testable import Common

final class SystemExtensionDiagnosticsTests: XCTestCase {
    
    private var diagnostics: SystemExtensionDiagnostics!
    private var tempDirectory: URL!
    private var testBundlePath: String!
    
    override func setUp() {
        super.setUp()
        
        diagnostics = SystemExtensionDiagnostics()
        
        // Create temporary directory for test bundles
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SystemExtensionDiagnosticsTests")
            .appendingPathComponent(UUID().uuidString)
        
        try! FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create a test bundle for validation
        testBundlePath = tempDirectory.appendingPathComponent("TestBundle.systemextension").path
        createTestBundle(at: testBundlePath)
    }
    
    override func tearDown() {
        // Clean up test files
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }
    
    // MARK: - Health Check Tests
    
    func testPerformHealthCheck_ReturnsReport() {
        let report = diagnostics.performHealthCheck()
        
        // Validate report structure
        XCTAssertNotNil(report)
        XCTAssertFalse(report.healthChecks.isEmpty, "Health report should contain health checks")
        XCTAssertGreaterThan(report.checkTime, 0, "Check time should be positive")
        XCTAssertFalse(report.systemInformation.isEmpty, "Should include system information")
        XCTAssertFalse(report.performanceMetrics.isEmpty, "Should include performance metrics")
        
        // Validate health status
        XCTAssertTrue([.healthy, .degraded, .unhealthy, .unknown].contains(report.overallHealth))
        
        // Validate system information includes expected keys
        XCTAssertNotNil(report.systemInformation["macos_version"])
        XCTAssertNotNil(report.systemInformation["sip_status"])
        
        // Validate performance metrics
        XCTAssertNotNil(report.performanceMetrics["health_check_duration"])
    }
    
    func testPerformHealthCheck_RecommendationsProvided() {
        let report = diagnostics.performHealthCheck()
        
        if report.overallHealth != .healthy {
            XCTAssertFalse(report.recommendations.isEmpty, "Unhealthy status should provide recommendations")
        }
        
        // Recommendations should be actionable
        for recommendation in report.recommendations {
            XCTAssertFalse(recommendation.isEmpty, "Recommendations should not be empty")
        }
    }
    
    // MARK: - Bundle Validation Tests
    
    func testValidateBundleIntegrity_ValidBundle() {
        let report = diagnostics.validateBundleIntegrity(bundlePath: testBundlePath)
        
        XCTAssertEqual(report.bundlePath, testBundlePath)
        XCTAssertGreaterThan(report.validationTime, 0)
        XCTAssertFalse(report.validationResults.isEmpty)
        
        // Should have some passing validations for a properly structured test bundle
        let passedValidations = report.validationResults.filter { $0.isValid }
        XCTAssertFalse(passedValidations.isEmpty, "Valid bundle should have some passing validations")
    }
    
    func testValidateBundleIntegrity_NonexistentBundle() {
        let nonexistentPath = tempDirectory.appendingPathComponent("Nonexistent.systemextension").path
        let report = diagnostics.validateBundleIntegrity(bundlePath: nonexistentPath)
        
        XCTAssertFalse(report.isValid)
        XCTAssertFalse(report.validationResults.isEmpty)
        
        // Should have validation result indicating bundle doesn't exist
        let existenceResults = report.validationResults.filter { result in
            result.validationName.lowercased().contains("exist")
        }
        XCTAssertFalse(existenceResults.isEmpty)
        XCTAssertFalse(existenceResults.first?.isValid ?? true)
    }
    
    func testValidateBundleIntegrity_IncompleteBundle() {
        // Create incomplete bundle (missing executable)
        let incompletePath = tempDirectory.appendingPathComponent("Incomplete.systemextension").path
        let incompleteURL = URL(fileURLWithPath: incompletePath)
        let contentsURL = incompleteURL.appendingPathComponent("Contents")
        
        try! FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        
        // Create Info.plist but no executable
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        let plistDict: [String: Any] = [
            "CFBundleIdentifier": "com.test.incomplete",
            "CFBundleExecutable": "NonexistentExecutable"
        ]
        let plistData = try! PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        try! plistData.write(to: infoPlistURL)
        
        let report = diagnostics.validateBundleIntegrity(bundlePath: incompletePath)
        
        XCTAssertFalse(report.isValid)
        
        // Should identify missing executable
        let executableResults = report.validationResults.filter { result in
            result.validationName.lowercased().contains("executable")
        }
        XCTAssertFalse(executableResults.isEmpty)
    }
    
    // MARK: - System Information Tests
    
    func testGetSystemInformation_ReturnsValidData() {
        let systemInfo = diagnostics.getSystemInformation()
        
        XCTAssertFalse(systemInfo.isEmpty)
        
        // Should include basic system information
        XCTAssertNotNil(systemInfo["macos_version"])
        XCTAssertNotNil(systemInfo["system_architecture"])
        
        if let macosVersion = systemInfo["macos_version"] as? String {
            XCTAssertFalse(macosVersion.isEmpty)
        }
    }
    
    func testGetSystemExtensionInformation() {
        let extensionInfo = diagnostics.getSystemExtensionInformation()
        
        XCTAssertNotNil(extensionInfo)
        
        // Should include extension-related information
        XCTAssertNotNil(extensionInfo["installed_extensions_count"])
        XCTAssertNotNil(extensionInfo["sip_status"])
        XCTAssertNotNil(extensionInfo["developer_mode_enabled"])
    }
    
    // MARK: - Performance Metrics Tests
    
    func testGetPerformanceMetrics() {
        let metrics = diagnostics.getPerformanceMetrics()
        
        XCTAssertFalse(metrics.isEmpty)
        
        // Should include basic performance metrics
        XCTAssertNotNil(metrics["memory_usage"])
        XCTAssertNotNil(metrics["cpu_usage"])
        
        // Metrics should be reasonable values
        if let memoryUsage = metrics["memory_usage"] as? Double {
            XCTAssertGreaterThanOrEqual(memoryUsage, 0)
        }
        
        if let cpuUsage = metrics["cpu_usage"] as? Double {
            XCTAssertGreaterThanOrEqual(cpuUsage, 0)
            XCTAssertLessThanOrEqual(cpuUsage, 100)
        }
    }
    
    // MARK: - Log Analysis Tests
    
    func testAnalyzeSystemLogs_ReturnsAnalysis() {
        let analysis = diagnostics.analyzeSystemLogs(timeRange: .lastHour)
        
        XCTAssertNotNil(analysis)
        XCTAssertGreaterThanOrEqual(analysis.totalLogEntries, 0)
        XCTAssertGreaterThanOrEqual(analysis.errorEntries.count, 0)
        XCTAssertGreaterThanOrEqual(analysis.warningEntries.count, 0)
        
        // Analysis should include timestamps
        XCTAssertNotNil(analysis.startTime)
        XCTAssertNotNil(analysis.endTime)
        XCTAssertLessThanOrEqual(analysis.startTime, analysis.endTime)
    }
    
    func testAnalyzeSystemLogs_FiltersByCategory() {
        let analysis = diagnostics.analyzeSystemLogs(
            timeRange: .lastHour,
            category: "com.apple.systemextensions"
        )
        
        XCTAssertNotNil(analysis)
        
        // Should have filtered results
        for entry in analysis.errorEntries {
            XCTAssertTrue(entry.category.contains("systemextensions") || entry.message.contains("systemextensions"))
        }
    }
    
    // MARK: - Troubleshooting Tests
    
    func testGenerateTroubleshootingReport() {
        let report = diagnostics.generateTroubleshootingReport()
        
        XCTAssertFalse(report.isEmpty)
        XCTAssertTrue(report.contains("System Extension Troubleshooting Report"))
        
        // Should include system information
        XCTAssertTrue(report.contains("System Information"))
        XCTAssertTrue(report.contains("macOS"))
        
        // Should include recommendations or next steps
        XCTAssertTrue(report.contains("Recommendation") || report.contains("Next Steps"))
    }
    
    func testGenerateTroubleshootingReport_WithBundle() {
        let report = diagnostics.generateTroubleshootingReport(bundlePath: testBundlePath)
        
        XCTAssertFalse(report.isEmpty)
        XCTAssertTrue(report.contains("Bundle Analysis"))
        XCTAssertTrue(report.contains(testBundlePath))
    }
    
    // MARK: - Diagnostic Result Tests
    
    func testDiagnosticResult_Severity() {
        let criticalResult = DiagnosticResult(
            checkName: "Critical Test",
            status: .failed,
            message: "Critical failure",
            severity: .critical,
            timestamp: Date()
        )
        
        XCTAssertEqual(criticalResult.severity, .critical)
        XCTAssertEqual(criticalResult.status, .failed)
        
        let infoResult = DiagnosticResult(
            checkName: "Info Test",
            status: .passed,
            message: "All good",
            severity: .info,
            timestamp: Date()
        )
        
        XCTAssertEqual(infoResult.severity, .info)
        XCTAssertEqual(infoResult.status, .passed)
    }
    
    func testHealthStatus_Ordering() {
        XCTAssertLessThan(HealthStatus.healthy.rawValue, HealthStatus.degraded.rawValue)
        XCTAssertLessThan(HealthStatus.degraded.rawValue, HealthStatus.unhealthy.rawValue)
    }
    
    // MARK: - IOKit Integration Tests
    
    func testCheckIOKitIntegration() {
        let result = diagnostics.checkIOKitIntegration()
        
        XCTAssertNotNil(result)
        XCTAssertFalse(result.checkName.isEmpty)
        
        // IOKit should generally be available on macOS systems
        if result.status == .passed {
            XCTAssertTrue(result.message.contains("available") || result.message.contains("working"))
        }
    }
    
    // MARK: - System Extension Communication Tests
    
    func testCheckSystemExtensionCommunication() {
        let result = diagnostics.checkSystemExtensionCommunication()
        
        XCTAssertNotNil(result)
        XCTAssertFalse(result.checkName.isEmpty)
        
        // Communication check should provide meaningful results
        XCTAssertFalse(result.message.isEmpty)
    }
    
    // MARK: - Error Recovery Tests
    
    func testSuggestErrorRecovery_ReturnsRecommendations() {
        let error = InstallationError.userApprovalRequired
        let recommendations = diagnostics.suggestErrorRecovery(for: error)
        
        XCTAssertFalse(recommendations.isEmpty)
        
        // Should provide specific recommendations for this error type
        let approvalRecommendations = recommendations.filter { recommendation in
            recommendation.lowercased().contains("approval") || recommendation.lowercased().contains("allow")
        }
        XCTAssertFalse(approvalRecommendations.isEmpty)
    }
    
    func testSuggestErrorRecovery_DifferentErrorTypes() {
        let bundleError = InstallationError.bundleCreationFailed("test")
        let bundleRecommendations = diagnostics.suggestErrorRecovery(for: bundleError)
        XCTAssertFalse(bundleRecommendations.isEmpty)
        
        let signingError = InstallationError.signingFailed("test")
        let signingRecommendations = diagnostics.suggestErrorRecovery(for: signingError)
        XCTAssertFalse(signingRecommendations.isEmpty)
        
        // Different error types should have different recommendations
        XCTAssertNotEqual(bundleRecommendations, signingRecommendations)
    }
    
    // MARK: - Helper Methods
    
    private func createTestBundle(at path: String) {
        let bundleURL = URL(fileURLWithPath: path)
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        let macosURL = contentsURL.appendingPathComponent("MacOS")
        let resourcesURL = contentsURL.appendingPathComponent("Resources")
        
        // Create directory structure
        try! FileManager.default.createDirectory(at: macosURL, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        
        // Create Info.plist
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        let plistDict: [String: Any] = [
            "CFBundleIdentifier": "com.test.systemextension",
            "CFBundleExecutable": "TestSystemExtension",
            "CFBundlePackageType": "SYSX",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "11.0",
            "NSSystemExtensionUsageDescription": "Test System Extension"
        ]
        
        let plistData = try! PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        try! plistData.write(to: infoPlistURL)
        
        // Create executable
        let executableURL = macosURL.appendingPathComponent("TestSystemExtension")
        let executableData = Data("mock system extension executable".utf8)
        try! executableData.write(to: executableURL)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
    }
}