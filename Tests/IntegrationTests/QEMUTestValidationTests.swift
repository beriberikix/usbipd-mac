import XCTest
import Foundation

/// Unit tests for QEMU test validation utilities
/// Tests the shell script functions through process execution
final class QEMUTestValidationTests: XCTestCase {
    
    private let scriptPath = "Scripts/qemu-test-validation.sh"
    private let testDataDir = ".build/qemu/test-data"
    
    override func setUp() {
        super.setUp()
        
        // Create test data directory
        let fileManager = FileManager.default
        try? fileManager.createDirectory(atPath: testDataDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        super.tearDown()
        
        // Clean up test data
        let fileManager = FileManager.default
        try? fileManager.removeItem(atPath: testDataDir)
    }
    
    // MARK: - Helper Functions
    
    private func createTestConsoleLog(content: String, filename: String = "test-console.log") -> String {
        let logPath = "\(testDataDir)/\(filename)"
        try? content.write(toFile: logPath, atomically: true, encoding: .utf8)
        return logPath
    }
    
    private func runScript(command: String, arguments: [String] = []) -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath, command] + arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            return (output, process.terminationStatus)
        } catch {
            return ("Error running script: \(error)", -1)
        }
    }
    
    // MARK: - Console Log Parsing Tests
    
    func testParseConsoleLogAllMessages() {
        let logContent = """
        [2024-01-15 10:30:15.123] USBIP_STARTUP_BEGIN
        [2024-01-15 10:30:15.456] VHCI_MODULE_LOADED: SUCCESS
        [2024-01-15 10:30:16.456] USBIP_CLIENT_READY
        [2024-01-15 10:30:17.890] TEST_COMPLETE: SUCCESS
        """
        
        let logPath = createTestConsoleLog(content: logContent)
        let result = runScript(command: "parse-log", arguments: [logPath])
        
        XCTAssertEqual(result.exitCode, 0, "Script should exit successfully")
        XCTAssertTrue(result.output.contains("USBIP_STARTUP_BEGIN"), "Should contain startup message")
        XCTAssertTrue(result.output.contains("VHCI_MODULE_LOADED"), "Should contain module loaded message")
        XCTAssertTrue(result.output.contains("USBIP_CLIENT_READY"), "Should contain client ready message")
        XCTAssertTrue(result.output.contains("TEST_COMPLETE"), "Should contain test complete message")
    }
    
    func testParseConsoleLogSpecificMessageType() {
        let logContent = """
        [2024-01-15 10:30:15.123] USBIP_STARTUP_BEGIN
        [2024-01-15 10:30:15.456] VHCI_MODULE_LOADED: SUCCESS
        [2024-01-15 10:30:16.456] USBIP_CLIENT_READY
        [2024-01-15 10:30:17.890] USBIP_CLIENT_READY
        """
        
        let logPath = createTestConsoleLog(content: logContent)
        let result = runScript(command: "parse-log", arguments: [logPath, "USBIP_CLIENT_READY"])
        
        XCTAssertEqual(result.exitCode, 0, "Script should exit successfully")
        XCTAssertTrue(result.output.contains("USBIP_CLIENT_READY"), "Should contain client ready messages")
        XCTAssertFalse(result.output.contains("VHCI_MODULE_LOADED"), "Should not contain other message types")
        
        // Should contain both USBIP_CLIENT_READY messages
        let readyCount = result.output.components(separatedBy: "USBIP_CLIENT_READY").count - 1
        XCTAssertEqual(readyCount, 2, "Should find exactly 2 USBIP_CLIENT_READY messages")
    }
    
    func testParseConsoleLogNonExistentFile() {
        let result = runScript(command: "parse-log", arguments: ["/nonexistent/file.log"])
        
        XCTAssertNotEqual(result.exitCode, 0, "Script should fail for non-existent file")
        XCTAssertTrue(result.output.contains("not found"), "Should indicate file not found")
    }
    
    // MARK: - USB/IP Client Readiness Tests
    
    func testCheckReadinessClientReady() {
        let logContent = """
        [2024-01-15 10:30:15.456] VHCI_MODULE_LOADED: SUCCESS
        [2024-01-15 10:30:16.456] USBIP_CLIENT_READY
        [2024-01-15 10:30:17.890] TEST_COMPLETE: SUCCESS
        """
        
        let logPath = createTestConsoleLog(content: logContent)
        let result = runScript(command: "check-readiness", arguments: [logPath])
        
        XCTAssertEqual(result.exitCode, 0, "Script should exit successfully when client is ready")
        XCTAssertTrue(result.output.contains("ready"), "Should indicate client is ready")
    }
    
    func testCheckReadinessClientNotReady() {
        let logContent = """
        [2024-01-15 10:30:15.456] VHCI_MODULE_LOADED: SUCCESS
        [2024-01-15 10:30:16.456] USBIP_STARTUP_BEGIN
        [2024-01-15 10:30:17.890] CONNECTING_TO_SERVER: 192.168.1.100:3240
        """
        
        let logPath = createTestConsoleLog(content: logContent)
        let result = runScript(command: "check-readiness", arguments: [logPath])
        
        XCTAssertNotEqual(result.exitCode, 0, "Script should fail when client is not ready")
        XCTAssertTrue(result.output.contains("not ready"), "Should indicate client is not ready")
    }
    
    func testWaitReadinessTimeout() {
        let logContent = """
        [2024-01-15 10:30:15.456] VHCI_MODULE_LOADED: SUCCESS
        [2024-01-15 10:30:16.456] USBIP_STARTUP_BEGIN
        """
        
        let logPath = createTestConsoleLog(content: logContent)
        
        // Use a very short timeout for testing
        let result = runScript(command: "wait-readiness", arguments: [logPath, "2"])
        
        XCTAssertNotEqual(result.exitCode, 0, "Script should timeout when client doesn't become ready")
        XCTAssertTrue(result.output.contains("timeout"), "Should indicate timeout occurred")
    }
    
    // MARK: - Test Validation Tests
    
    func testValidateTestSuccess() {
        let logContent = """
        [2024-01-15 10:30:15.456] USBIP_CLIENT_READY
        [2024-01-15 10:30:16.456] DEVICE_LIST_REQUEST: SUCCESS
        [2024-01-15 10:30:17.890] TEST_COMPLETE: SUCCESS
        """
        
        let logPath = createTestConsoleLog(content: logContent)
        let result = runScript(command: "validate-test", arguments: [logPath])
        
        XCTAssertEqual(result.exitCode, 0, "Script should exit successfully for successful test")
        XCTAssertTrue(result.output.contains("SUCCESS"), "Should indicate test success")
    }
    
    func testValidateTestFailure() {
        let logContent = """
        [2024-01-15 10:30:15.456] USBIP_CLIENT_READY
        [2024-01-15 10:30:16.456] DEVICE_LIST_REQUEST: FAILED
        [2024-01-15 10:30:17.890] TEST_COMPLETE: FAILED
        """
        
        let logPath = createTestConsoleLog(content: logContent)
        let result = runScript(command: "validate-test", arguments: [logPath])
        
        XCTAssertNotEqual(result.exitCode, 0, "Script should fail for failed test")
        XCTAssertTrue(result.output.contains("FAILED"), "Should indicate test failure")
    }
    
    func testValidateTestNoCompletion() {
        let logContent = """
        [2024-01-15 10:30:15.456] USBIP_CLIENT_READY
        [2024-01-15 10:30:16.456] DEVICE_LIST_REQUEST: SUCCESS
        """
        
        let logPath = createTestConsoleLog(content: logContent)
        let result = runScript(command: "validate-test", arguments: [logPath])
        
        XCTAssertNotEqual(result.exitCode, 0, "Script should fail when no completion message found")
        XCTAssertTrue(result.output.contains("No test completion"), "Should indicate missing completion message")
    }
    
    // MARK: - Test Report Generation Tests
    
    func testGenerateReport() {
        let logContent = """
        [2024-01-15 10:30:15.456] USBIP_CLIENT_READY
        [2024-01-15 10:30:16.456] VHCI_MODULE_LOADED: SUCCESS
        [2024-01-15 10:30:17.456] USBIP_VERSION: usbip (usbip-utils 2.0)
        [2024-01-15 10:30:18.456] DEVICE_LIST_REQUEST: SUCCESS
        [2024-01-15 10:30:19.890] TEST_COMPLETE: SUCCESS
        """
        
        let logPath = createTestConsoleLog(content: logContent)
        let reportPath = "\(testDataDir)/test-report.txt"
        let result = runScript(command: "generate-report", arguments: [logPath, reportPath])
        
        XCTAssertEqual(result.exitCode, 0, "Script should exit successfully when generating report")
        XCTAssertTrue(result.output.contains("generated"), "Should indicate report was generated")
        
        // Verify report file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportPath), "Report file should be created")
        
        // Verify report content
        if let reportContent = try? String(contentsOfFile: reportPath) {
            XCTAssertTrue(reportContent.contains("Test Report"), "Report should contain title")
            XCTAssertTrue(reportContent.contains("Readiness Status"), "Report should contain readiness status")
            XCTAssertTrue(reportContent.contains("Test Timeline"), "Report should contain timeline")
            XCTAssertTrue(reportContent.contains("Test Summary"), "Report should contain summary")
        } else {
            XCTFail("Could not read generated report file")
        }
    }
    
    // MARK: - Server Connectivity Tests
    
    func testCheckServerConnectivityInvalidHost() {
        // Test with an invalid host that should fail quickly
        let result = runScript(command: "check-server", arguments: ["invalid.nonexistent.host", "3240"])
        
        XCTAssertNotEqual(result.exitCode, 0, "Script should fail for invalid host")
        XCTAssertTrue(result.output.contains("not reachable"), "Should indicate server is not reachable")
    }
    
    func testCheckServerConnectivityLocalhost() {
        // Test with localhost on a port that's likely not in use
        let result = runScript(command: "check-server", arguments: ["localhost", "65432"])
        
        // This should fail since nothing is listening on port 65432
        XCTAssertNotEqual(result.exitCode, 0, "Script should fail when no server is listening")
        XCTAssertTrue(result.output.contains("not reachable"), "Should indicate server is not reachable")
    }
    
    // MARK: - Log Format Validation Tests
    
    func testValidateLogFormatValid() {
        let logContent = """
        [2024-01-15 10:30:15.456] USBIP_CLIENT_READY
        [2024-01-15 10:30:16.789] VHCI_MODULE_LOADED: SUCCESS
        [2024-01-15 10:30:17.123] TEST_COMPLETE: SUCCESS
        """
        
        let logPath = createTestConsoleLog(content: logContent)
        let result = runScript(command: "validate-format", arguments: [logPath])
        
        XCTAssertEqual(result.exitCode, 0, "Script should exit successfully for valid format")
        XCTAssertTrue(result.output.contains("validation passed"), "Should indicate validation passed")
    }
    
    func testValidateLogFormatInvalid() {
        let logContent = """
        Invalid log message without timestamp
        Another invalid message
        Yet another invalid message
        """
        
        let logPath = createTestConsoleLog(content: logContent)
        let result = runScript(command: "validate-format", arguments: [logPath])
        
        XCTAssertNotEqual(result.exitCode, 0, "Script should fail for invalid format")
        XCTAssertTrue(result.output.contains("No structured messages"), "Should indicate no structured messages found")
    }
    
    // MARK: - Statistics Tests
    
    func testGetTestStatistics() {
        let logContent = """
        [2024-01-15 10:30:15.456] USBIP_CLIENT_READY
        [2024-01-15 10:30:16.456] VHCI_MODULE_LOADED: SUCCESS
        [2024-01-15 10:30:17.456] CONNECTING_TO_SERVER: 192.168.1.100:3240
        [2024-01-15 10:30:18.456] DEVICE_LIST_REQUEST: SUCCESS
        [2024-01-15 10:30:19.456] DEVICE_IMPORT_REQUEST: 1-1 SUCCESS
        [2024-01-15 10:30:20.456] DEVICE_IMPORT_REQUEST: 1-2 SUCCESS
        [2024-01-15 10:30:21.456] TEST_COMPLETE: SUCCESS
        """
        
        let logPath = createTestConsoleLog(content: logContent)
        let result = runScript(command: "get-stats", arguments: [logPath])
        
        XCTAssertEqual(result.exitCode, 0, "Script should exit successfully when getting statistics")
        XCTAssertTrue(result.output.contains("USBIP_CLIENT_READY:"), "Should show client ready count")
        XCTAssertTrue(result.output.contains("VHCI_MODULE_LOADED:"), "Should show module loaded count")
        XCTAssertTrue(result.output.contains("CONNECTING_TO_SERVER:"), "Should show connection count")
        XCTAssertTrue(result.output.contains("DEVICE_LIST_REQUEST:"), "Should show device list count")
        XCTAssertTrue(result.output.contains("DEVICE_IMPORT_REQUEST:"), "Should show device import count")
        XCTAssertTrue(result.output.contains("TEST_COMPLETE:"), "Should show test completion count")
    }
    
    // MARK: - Error Handling Tests
    
    func testScriptWithInvalidCommand() {
        let result = runScript(command: "invalid-command")
        
        XCTAssertNotEqual(result.exitCode, 0, "Script should fail for invalid command")
        XCTAssertTrue(result.output.contains("Unknown command"), "Should indicate unknown command")
    }
    
    func testScriptWithMissingArguments() {
        let result = runScript(command: "parse-log")
        
        XCTAssertNotEqual(result.exitCode, 0, "Script should fail when required arguments are missing")
        XCTAssertTrue(result.output.contains("Usage:"), "Should show usage information")
    }
    
    func testScriptHelp() {
        let result = runScript(command: "--help")
        
        XCTAssertEqual(result.exitCode, 0, "Script should exit successfully when showing help")
        XCTAssertTrue(result.output.contains("Usage:"), "Should show usage information")
        XCTAssertTrue(result.output.contains("COMMANDS:"), "Should show available commands")
        XCTAssertTrue(result.output.contains("EXAMPLES:"), "Should show examples")
    }
    
    // MARK: - Integration Tests
    
    func testCompleteWorkflow() {
        let logContent = """
        [2024-01-15 10:30:15.123] USBIP_STARTUP_BEGIN
        [2024-01-15 10:30:15.456] VHCI_MODULE_LOADED: SUCCESS
        [2024-01-15 10:30:16.456] USBIP_CLIENT_READY
        [2024-01-15 10:30:17.456] USBIP_VERSION: usbip (usbip-utils 2.0)
        [2024-01-15 10:30:18.456] CONNECTING_TO_SERVER: 192.168.1.100:3240
        [2024-01-15 10:30:19.456] DEVICE_LIST_REQUEST: SUCCESS
        [2024-01-15 10:30:20.456] DEVICE_IMPORT_REQUEST: 1-1 SUCCESS
        [2024-01-15 10:30:21.456] TEST_COMPLETE: SUCCESS
        """
        
        let logPath = createTestConsoleLog(content: logContent)
        
        // Test complete workflow: format validation -> readiness check -> test validation -> report generation
        
        // 1. Validate format
        let formatResult = runScript(command: "validate-format", arguments: [logPath])
        XCTAssertEqual(formatResult.exitCode, 0, "Format validation should pass")
        
        // 2. Check readiness
        let readinessResult = runScript(command: "check-readiness", arguments: [logPath])
        XCTAssertEqual(readinessResult.exitCode, 0, "Readiness check should pass")
        
        // 3. Validate test
        let testResult = runScript(command: "validate-test", arguments: [logPath])
        XCTAssertEqual(testResult.exitCode, 0, "Test validation should pass")
        
        // 4. Generate report
        let reportPath = "\(testDataDir)/workflow-report.txt"
        let reportResult = runScript(command: "generate-report", arguments: [logPath, reportPath])
        XCTAssertEqual(reportResult.exitCode, 0, "Report generation should pass")
        
        // 5. Get statistics
        let statsResult = runScript(command: "get-stats", arguments: [logPath])
        XCTAssertEqual(statsResult.exitCode, 0, "Statistics generation should pass")
        
        // Verify all steps completed successfully
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportPath), "Report should be generated")
    }
}