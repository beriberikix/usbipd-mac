import XCTest
@testable import Common

final class LoggerTests: XCTestCase {
    
    func testLogLevelComparison() {
        XCTAssertTrue(LogLevel.debug < LogLevel.info)
        XCTAssertTrue(LogLevel.info < LogLevel.warning)
        XCTAssertTrue(LogLevel.warning < LogLevel.error)
        XCTAssertTrue(LogLevel.error < LogLevel.critical)
        
        XCTAssertFalse(LogLevel.critical < LogLevel.debug)
        XCTAssertFalse(LogLevel.error < LogLevel.warning)
    }
    
    func testLogLevelDescription() {
        XCTAssertEqual(LogLevel.debug.description, "DEBUG")
        XCTAssertEqual(LogLevel.info.description, "INFO")
        XCTAssertEqual(LogLevel.warning.description, "WARNING")
        XCTAssertEqual(LogLevel.error.description, "ERROR")
        XCTAssertEqual(LogLevel.critical.description, "CRITICAL")
    }
    
    func testLoggerConfigDefaults() {
        let config = LoggerConfig()
        
        XCTAssertEqual(config.level, .info)
        XCTAssertTrue(config.includeTimestamp)
        XCTAssertFalse(config.includeContext)
        XCTAssertEqual(config.dateFormatter.dateFormat, "yyyy-MM-dd HH:mm:ss.SSS")
    }
    
    func testLoggerConfigCustomization() {
        let config = LoggerConfig(
            level: .debug,
            includeTimestamp: false,
            includeContext: true
        )
        
        XCTAssertEqual(config.level, .debug)
        XCTAssertFalse(config.includeTimestamp)
        XCTAssertTrue(config.includeContext)
    }
    
    func testLoggerInitialization() {
        let config = LoggerConfig(level: .warning)
        let logger = Logger(config: config, subsystem: "test", category: "test")
        
        // Logger should be initialized without throwing
        XCTAssertNotNil(logger)
    }
    
    func testSharedLoggerExists() {
        XCTAssertNotNil(Logger.shared)
    }
    
    func testLogLevelFiltering() {
        // Create a logger with warning level
        let config = LoggerConfig(level: .warning, includeTimestamp: false, includeContext: false)
        let logger = Logger(config: config)
        
        // These tests verify that the logger respects the configured level
        // In a real implementation, we would need to capture the output to verify
        // For now, we just ensure the methods don't crash
        logger.debug("This should not be logged")
        logger.info("This should not be logged")
        logger.warning("This should be logged")
        logger.error("This should be logged")
        logger.critical("This should be logged")
    }
    
    func testConvenienceMethods() {
        let logger = Logger()
        
        // Test that convenience methods don't crash
        logger.debug("Debug message")
        logger.info("Info message")
        logger.warning("Warning message")
        logger.error("Error message")
        logger.critical("Critical message")
    }
    
    func testErrorLogging() {
        let logger = Logger()
        let testError = NSError(domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        
        // Test error logging with Error object
        logger.error(testError)
        logger.error(testError, message: "Custom error message")
        logger.error(testError, context: ["key": "value"])
    }
    
    func testContextLogging() {
        let logger = Logger()
        let context: [String: Any] = ["userId": "123", "action": "login", "timestamp": Date()]
        
        // Test logging with context
        logger.info("User action", context: context)
        logger.error("Action failed", context: context)
    }
    
    func testGlobalLoggingFunctions() {
        // Test that global functions don't crash
        logDebug("Global debug")
        logInfo("Global info")
        logWarning("Global warning")
        logError("Global error")
        logCritical("Global critical")
        
        let testError = NSError(domain: "TestDomain", code: 456, userInfo: nil)
        logError(testError)
        logError(testError, message: "Global error with message")
    }
    
    func testThreadSafety() {
        let logger = Logger()
        let expectation = XCTestExpectation(description: "Concurrent logging")
        expectation.expectedFulfillmentCount = 10
        
        // Test concurrent logging from multiple threads
        for i in 0..<10 {
            DispatchQueue.global().async {
                logger.info("Concurrent message \(i)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testMessageFormatting() {
        // Test with timestamp and context disabled for predictable output
        let config = LoggerConfig(level: .debug, includeTimestamp: false, includeContext: false)
        let logger = Logger(config: config)
        
        // Since we can't easily capture the formatted output in this test setup,
        // we just verify the logger doesn't crash with various inputs
        logger.info("Simple message")
        logger.error("Error message", context: ["error_code": 500])
        logger.debug("Debug message", context: ["module": "network", "connection_id": "abc123"])
    }
    
    func testLogLevelAllCases() {
        // Ensure all log levels are covered
        let allLevels = LogLevel.allCases
        XCTAssertEqual(allLevels.count, 5)
        XCTAssertTrue(allLevels.contains(.debug))
        XCTAssertTrue(allLevels.contains(.info))
        XCTAssertTrue(allLevels.contains(.warning))
        XCTAssertTrue(allLevels.contains(.error))
        XCTAssertTrue(allLevels.contains(.critical))
    }
    
    func testDateFormatterConfiguration() {
        let config = LoggerConfig()
        let formatter = config.dateFormatter
        
        // Test that the date formatter produces expected format
        let testDate = Date(timeIntervalSince1970: 1640995200) // 2022-01-01 00:00:00 UTC
        let formatted = formatter.string(from: testDate)
        
        // Should match the pattern yyyy-MM-dd HH:mm:ss.SSS
        XCTAssertTrue(formatted.contains("2022-01-01") || formatted.contains("2021-12-31"))
        XCTAssertTrue(formatted.contains(":"))
        XCTAssertTrue(formatted.contains("."))
    }
}