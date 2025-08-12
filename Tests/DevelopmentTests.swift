// DevelopmentTests.swift
// Development Test Environment - Fast unit tests with comprehensive mocking
// Consolidates business logic tests from USBIPDCoreTests and USBIPDCLITests for rapid development feedback
// Target execution time: <1 minute

import XCTest
import Foundation
@testable import USBIPDCore
@testable import USBIPDCLI
@testable import Common

final class DevelopmentTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol Implementation
    
    public static let testEnvironment: TestEnvironment = .development
    public static let requiredCapabilities: TestEnvironmentCapabilities = [.mockingSupport, .unitTestingCapable]
    
    // MARK: - Test Setup
    
    override static func setUp() {
        super.setUp()
        
        // Validate environment is suitable for development testing
        let config = TestEnvironmentConfig.current
        guard config.environment == .development else {
            XCTFail("Development tests should only run in development environment")
            return
        }
        
        // Enable comprehensive mocking for fast execution
        TestEnvironmentConfig.enableMocking(true)
        TestEnvironmentConfig.setExecutionTimeout(60.0) // 1 minute limit
    }
    
    override func setUp() {
        super.setUp()
        // Each test starts with clean state
        continueAfterFailure = false
    }
    
    // MARK: - USB/IP Protocol Encoding Tests (from EncodingTests.swift)
    
    func testUSBIPHeaderEncoding() throws {
        let header = USBIPHeader(
            version: 0x0111,
            command: .requestDeviceList,
            status: 0
        )
        
        let encodedData = try header.encode()
        XCTAssertEqual(encodedData.count, 8)
        
        let decodedHeader = try USBIPHeader.decode(from: encodedData)
        XCTAssertEqual(decodedHeader.version, header.version)
        XCTAssertEqual(decodedHeader.command, header.command)
        XCTAssertEqual(decodedHeader.status, header.status)
    }
    
    func testDeviceListRequestEncoding() throws {
        let request = DeviceListRequest()
        let encodedData = try request.encode()
        
        XCTAssertEqual(encodedData.count, 8)
        
        let decodedRequest = try DeviceListRequest.decode(from: encodedData)
        XCTAssertEqual(decodedRequest.header.command, .requestDeviceList)
    }
    
    func testUSBIPExportedDeviceEncoding() throws {
        let device = USBDeviceTestFixtures.appleMagicMouse.toUSBIPExportedDevice()
        
        let encodedData = try device.encode()
        XCTAssertEqual(encodedData.count, 312)
        
        let decodedDevice = try USBIPExportedDevice.decode(from: encodedData)
        USBDeviceAssertions.assertExportedDevicesEqual(device, decodedDevice)
    }
    
    func testDeviceImportRequestEncoding() throws {
        let request = DeviceImportRequest(busID: "1-1")
        let encodedData = try request.encode()
        
        XCTAssertEqual(encodedData.count, 40)
        
        let decodedRequest = try DeviceImportRequest.decode(from: encodedData)
        XCTAssertEqual(decodedRequest.busID, request.busID)
        XCTAssertEqual(decodedRequest.header.command, .requestDeviceImport)
    }
    
    func testEndiannessHandling() throws {
        let originalValue16: UInt16 = 0x1234
        let originalValue32: UInt32 = 0x12345678
        
        let networkValue16 = EndiannessConverter.toNetworkByteOrder(originalValue16)
        let networkValue32 = EndiannessConverter.toNetworkByteOrder(originalValue32)
        
        let restoredValue16 = EndiannessConverter.fromNetworkByteOrder(networkValue16)
        let restoredValue32 = EndiannessConverter.fromNetworkByteOrder(networkValue32)
        
        XCTAssertEqual(restoredValue16, originalValue16)
        XCTAssertEqual(restoredValue32, originalValue32)
    }
    
    // MARK: - Server Configuration Tests (from ServerConfigTests.swift)
    
    func testServerConfigDefaultInitialization() {
        let config = ServerConfig()
        
        XCTAssertEqual(config.port, ServerConfig.defaultPort)
        XCTAssertEqual(config.logLevel, ServerConfig.defaultLogLevel)
        XCTAssertFalse(config.debugMode)
        XCTAssertEqual(config.maxConnections, 10)
        XCTAssertEqual(config.connectionTimeout, 30.0)
        XCTAssertTrue(config.allowedDevices.isEmpty)
        XCTAssertFalse(config.autoBindDevices)
        XCTAssertNil(config.logFilePath)
    }
    
    func testServerConfigCustomInitialization() {
        let config = ServerConfig(
            port: 3241,
            logLevel: .debug,
            debugMode: true,
            maxConnections: 5,
            connectionTimeout: 60.0,
            allowedDevices: ["device1", "device2"],
            autoBindDevices: true,
            logFilePath: "/tmp/usbipd.log"
        )
        
        XCTAssertEqual(config.port, 3241)
        XCTAssertEqual(config.logLevel, .debug)
        XCTAssertTrue(config.debugMode)
        XCTAssertEqual(config.maxConnections, 5)
        XCTAssertEqual(config.connectionTimeout, 60.0)
        XCTAssertEqual(config.allowedDevices, ["device1", "device2"])
        XCTAssertTrue(config.autoBindDevices)
        XCTAssertEqual(config.logFilePath, "/tmp/usbipd.log")
    }
    
    func testServerConfigValidation() {
        var config = ServerConfig(port: 0)
        XCTAssertThrowsError(try config.validate()) { error in
            guard case ServerError.initializationFailed(_) = error else {
                XCTFail("Expected ServerError.initializationFailed")
                return
            }
        }
        
        config = ServerConfig(maxConnections: 0)
        XCTAssertThrowsError(try config.validate()) { error in
            guard case ServerError.initializationFailed(_) = error else {
                XCTFail("Expected ServerError.initializationFailed")
                return
            }
        }
        
        config = ServerConfig()
        XCTAssertNoThrow(try config.validate())
    }
    
    func testServerConfigDeviceAllowance() {
        let config = ServerConfig()
        
        XCTAssertTrue(config.isDeviceAllowed("any-device"))
        
        config.allowedDevices = ["device1", "device2"]
        XCTAssertTrue(config.isDeviceAllowed("device1"))
        XCTAssertFalse(config.isDeviceAllowed("device3"))
        
        config.allowDevice("device3")
        XCTAssertTrue(config.isDeviceAllowed("device3"))
        
        let removed = config.disallowDevice("device2")
        XCTAssertTrue(removed)
        XCTAssertFalse(config.isDeviceAllowed("device2"))
    }
    
    // MARK: - Logger Tests (from LoggerTests.swift)
    
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
        
        XCTAssertNotNil(logger)
    }
    
    // MARK: - USB/IP Message Tests (from USBIPMessagesTests.swift)
    
    func testUSBIPSubmitRequestControlTransfer() throws {
        let setupPacket = Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00])
        
        let request = USBIPSubmitRequest(
            seqnum: 1,
            devid: 1,
            direction: 1, // IN
            ep: 0x00,
            transferFlags: 0,
            transferBufferLength: 18,
            setup: setupPacket
        )
        
        let encodedData = try request.encode()
        XCTAssertEqual(encodedData.count, 60)
        
        let decodedRequest = try USBIPSubmitRequest.decode(from: encodedData)
        XCTAssertEqual(decodedRequest.ep, 0x00)
        XCTAssertEqual(decodedRequest.direction, 1)
        XCTAssertEqual(decodedRequest.transferBufferLength, 18)
        XCTAssertEqual(decodedRequest.setup, setupPacket)
        XCTAssertNil(decodedRequest.transferBuffer)
    }
    
    func testUSBIPSubmitRequestBulkTransfer() throws {
        let testData = Data(repeating: 0x42, count: 512)
        
        let request = USBIPSubmitRequest(
            seqnum: 2,
            devid: 1,
            direction: 0, // OUT
            ep: 0x02,
            transferFlags: 0,
            transferBufferLength: 512,
            transferBuffer: testData
        )
        
        let encodedData = try request.encode()
        XCTAssertEqual(encodedData.count, 572)
        
        let decodedRequest = try USBIPSubmitRequest.decode(from: encodedData)
        XCTAssertEqual(decodedRequest.ep, 0x02)
        XCTAssertEqual(decodedRequest.direction, 0)
        XCTAssertEqual(decodedRequest.transferBufferLength, 512)
        XCTAssertEqual(decodedRequest.transferBuffer, testData)
    }
    
    // MARK: - Command Line Parser Tests (from CommandLineParserTests.swift)
    
    func testCommandLineParserInitialization() {
        let mockDeviceDiscovery = MockDeviceDiscovery()
        let mockServerConfig = ServerConfig()
        let mockServer = MockUSBIPServer()
        let parser = CommandLineParser(deviceDiscovery: mockDeviceDiscovery, serverConfig: mockServerConfig, server: mockServer)
        
        XCTAssertNotNil(parser)
        
        let commands = parser.getCommands()
        XCTAssertFalse(commands.isEmpty)
        
        let commandNames = commands.map { $0.name }
        XCTAssertTrue(commandNames.contains("help"))
        XCTAssertTrue(commandNames.contains("list"))
        XCTAssertTrue(commandNames.contains("bind"))
        XCTAssertTrue(commandNames.contains("unbind"))
        XCTAssertTrue(commandNames.contains("daemon"))
    }
    
    func testCommandLineParserErrorHandling() {
        let mockDeviceDiscovery = MockDeviceDiscovery()
        let mockServerConfig = ServerConfig()
        let mockServer = MockUSBIPServer()
        let parser = CommandLineParser(deviceDiscovery: mockDeviceDiscovery, serverConfig: mockServerConfig, server: mockServer)
        
        XCTAssertThrowsError(try parser.parse(arguments: ["program", "unknown"])) { error in
            guard let commandError = error as? CommandLineError else {
                XCTFail("Expected CommandLineError")
                return
            }
            
            if case .unknownCommand(let cmd) = commandError {
                XCTAssertEqual(cmd, "unknown")
            } else {
                XCTFail("Expected unknownCommand error")
            }
        }
        
        XCTAssertThrowsError(try parser.parse(arguments: ["program", "bind"])) { error in
            guard let commandError = error as? CommandLineError else {
                XCTFail("Expected CommandLineError")
                return
            }
            
            if case .missingArguments = commandError {
                // Expected error
            } else {
                XCTFail("Expected missingArguments error")
            }
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testProtocolErrorHandling() throws {
        let shortData = Data([0x01, 0x11, 0x80])
        
        XCTAssertThrowsError(try USBIPMessageDecoder.validateHeader(in: shortData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
            if case USBIPProtocolError.invalidDataLength = error {
                // Expected error
            } else {
                XCTFail("Expected invalidDataLength error")
            }
        }
    }
    
    func testUnsupportedVersionHandling() throws {
        var invalidVersionData = Data()
        invalidVersionData.append(EndiannessConverter.writeUInt16ToData(0x0200))
        invalidVersionData.append(EndiannessConverter.writeUInt16ToData(USBIPProtocol.Command.requestDeviceList.rawValue))
        invalidVersionData.append(EndiannessConverter.writeUInt32ToData(0))
        
        XCTAssertThrowsError(try USBIPMessageDecoder.validateHeader(in: invalidVersionData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
            if case USBIPProtocolError.unsupportedVersion(let version) = error {
                XCTAssertEqual(version, 0x0200)
            } else {
                XCTFail("Expected unsupportedVersion error")
            }
        }
    }
    
    // MARK: - Message Encoder/Decoder Utility Tests
    
    func testMessageEncoderUtilities() throws {
        let devices = [USBDeviceTestFixtures.appleMagicMouse.toUSBIPExportedDevice()]
        
        let deviceListRequestData = try USBIPMessageEncoder.encodeDeviceListRequest()
        XCTAssertEqual(deviceListRequestData.count, 8)
        
        let deviceListResponseData = try USBIPMessageEncoder.encodeDeviceListResponse(devices: devices)
        XCTAssertEqual(deviceListResponseData.count, 328)
        
        let deviceImportRequestData = try USBIPMessageEncoder.encodeDeviceImportRequest(busID: "1-1")
        XCTAssertEqual(deviceImportRequestData.count, 40)
    }
    
    func testMessageDecoderUtilities() throws {
        let deviceListRequestData = try USBIPMessageEncoder.encodeDeviceListRequest()
        let decodedRequest = try USBIPMessageDecoder.decodeDeviceListRequest(from: deviceListRequestData)
        XCTAssertEqual(decodedRequest.header.command, .requestDeviceList)
        
        let deviceImportRequestData = try USBIPMessageEncoder.encodeDeviceImportRequest(busID: "test-device")
        let decodedImportRequest = try USBIPMessageDecoder.decodeDeviceImportRequest(from: deviceImportRequestData)
        XCTAssertEqual(decodedImportRequest.busID, "test-device")
        XCTAssertEqual(decodedImportRequest.header.command, .requestDeviceImport)
    }
    
    func testGenericMessageDecoding() throws {
        let deviceListRequestData = try USBIPMessageEncoder.encodeDeviceListRequest()
        let decodedMessage = try USBIPMessageDecoder.decodeMessage(from: deviceListRequestData)
        
        XCTAssertTrue(decodedMessage is DeviceListRequest)
        if let request = decodedMessage as? DeviceListRequest {
            XCTAssertEqual(request.header.command, .requestDeviceList)
        }
    }
    
    func testHeaderValidation() throws {
        let validData = try USBIPMessageEncoder.encodeDeviceListRequest()
        let header = try USBIPMessageDecoder.validateHeader(in: validData)
        XCTAssertEqual(header.version, USBIPProtocol.version)
        XCTAssertEqual(header.command, .requestDeviceList)
        
        let command = try USBIPMessageDecoder.peekCommand(in: validData)
        XCTAssertEqual(command, .requestDeviceList)
    }
    
    func testMessageIntegrityValidation() throws {
        let validData = try USBIPMessageEncoder.encodeDeviceListRequest()
        let isValid = try USBIPMessageDecoder.validateMessageIntegrity(data: validData)
        XCTAssertTrue(isValid)
        
        let malformedData = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        let isMalformedValid = try USBIPMessageDecoder.validateMessageIntegrity(data: malformedData)
        XCTAssertFalse(isMalformedValid)
    }
    
    // MARK: - String Encoding Utilities Tests
    
    func testStringEncodingUtilities() throws {
        let testString = "test-device"
        let encodedData = try StringEncodingUtilities.encodeFixedLengthString(testString, length: 32)
        
        XCTAssertEqual(encodedData.count, 32)
        
        let decodedString = try StringEncodingUtilities.decodeFixedLengthString(from: encodedData, at: 0, length: 32)
        XCTAssertEqual(decodedString, testString)
    }
    
    // MARK: - Performance Tests for Development Environment
    
    func testEncodingPerformance() {
        let device = USBDeviceTestFixtures.appleMagicMouse.toUSBIPExportedDevice()
        
        measure {
            for _ in 0..<100 {
                _ = try? device.encode()
            }
        }
    }
    
    func testDecodingPerformance() throws {
        let device = USBDeviceTestFixtures.appleMagicMouse.toUSBIPExportedDevice()
        let encodedData = try device.encode()
        
        measure {
            for _ in 0..<100 {
                _ = try? USBIPExportedDevice.decode(from: encodedData)
            }
        }
    }
    
    func testMessageProcessingPerformance() {
        measure {
            for _ in 0..<50 {
                _ = try? USBIPMessageEncoder.encodeDeviceListRequest()
            }
        }
    }
}

// MARK: - Test Suite Validation

extension DevelopmentTests {
    
    override func tearDown() {
        super.tearDown()
        
        // Validate test execution time is within development environment limits
        let executionTime = Date().timeIntervalSince(Date())
        let limit = TestEnvironment.development.executionTimeLimit
        
        if executionTime > limit {
            XCTFail("Development test execution exceeded time limit: \(executionTime)s > \(limit)s")
        }
    }
}