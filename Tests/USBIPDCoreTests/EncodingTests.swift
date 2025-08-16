// EncodingTests.swift
// Tests for USB/IP message encoding functionality

import XCTest
@testable import USBIPDCore
import Common

final class EncodingTests: XCTestCase {
    
    func testUSBIPHeaderEncoding() throws {
        // Test encoding a USB/IP header
        let header = USBIPHeader(
            version: 0x0111,
            command: .requestDeviceList,
            status: 0
        )
        
        let encodedData = try header.encode()
        
        // Verify the encoded data has the correct length (8 bytes)
        XCTAssertEqual(encodedData.count, 8)
        
        // Verify the data can be decoded back correctly
        let decodedHeader = try USBIPHeader.decode(from: encodedData)
        XCTAssertEqual(decodedHeader.version, header.version)
        XCTAssertEqual(decodedHeader.command, header.command)
        XCTAssertEqual(decodedHeader.status, header.status)
    }
    
    func testDeviceListRequestEncoding() throws {
        // Test encoding a device list request
        let request = DeviceListRequest()
        let encodedData = try request.encode()
        
        // Verify the encoded data has the correct length (8 bytes for header)
        XCTAssertEqual(encodedData.count, 8)
        
        // Verify the data can be decoded back correctly
        let decodedRequest = try DeviceListRequest.decode(from: encodedData)
        XCTAssertEqual(decodedRequest.header.command, .requestDeviceList)
    }
    
    func testUSBIPExportedDeviceEncoding() throws {
        // Test encoding an exported device
        let device = USBIPExportedDevice(
            path: "/sys/devices/pci0000:00/0000:00:14.0/usb1/1-1",
            busID: "1-1",
            busnum: 1,
            devnum: 2,
            speed: 480000000, // High speed USB
            vendorID: 0x1234,
            productID: 0x5678,
            deviceClass: 9, // Hub class
            deviceSubClass: 0,
            deviceProtocol: 1,
            configurationCount: 1,
            configurationValue: 1,
            interfaceCount: 1
        )
        
        let encodedData = try device.encode()
        
        // Verify the encoded data has the correct length (312 bytes)
        XCTAssertEqual(encodedData.count, 312)
        
        // Verify the data can be decoded back correctly
        let decodedDevice = try USBIPExportedDevice.decode(from: encodedData)
        XCTAssertEqual(decodedDevice.path, device.path)
        XCTAssertEqual(decodedDevice.busID, device.busID)
        XCTAssertEqual(decodedDevice.busnum, device.busnum)
        XCTAssertEqual(decodedDevice.devnum, device.devnum)
        XCTAssertEqual(decodedDevice.speed, device.speed)
        XCTAssertEqual(decodedDevice.vendorID, device.vendorID)
        XCTAssertEqual(decodedDevice.productID, device.productID)
        XCTAssertEqual(decodedDevice.deviceClass, device.deviceClass)
        XCTAssertEqual(decodedDevice.deviceSubClass, device.deviceSubClass)
        XCTAssertEqual(decodedDevice.deviceProtocol, device.deviceProtocol)
        XCTAssertEqual(decodedDevice.configurationCount, device.configurationCount)
        XCTAssertEqual(decodedDevice.configurationValue, device.configurationValue)
        XCTAssertEqual(decodedDevice.interfaceCount, device.interfaceCount)
    }
    
    func testDeviceListResponseEncoding() throws {
        // Test encoding a device list response with multiple devices
        let device1 = USBIPExportedDevice(
            path: "/sys/devices/pci0000:00/0000:00:14.0/usb1/1-1",
            busID: "1-1",
            busnum: 1,
            devnum: 2,
            speed: 480000000,
            vendorID: 0x1234,
            productID: 0x5678,
            deviceClass: 9,
            deviceSubClass: 0,
            deviceProtocol: 1,
            configurationCount: 1,
            configurationValue: 1,
            interfaceCount: 1
        )
        
        let device2 = USBIPExportedDevice(
            path: "/sys/devices/pci0000:00/0000:00:14.0/usb1/1-2",
            busID: "1-2",
            busnum: 1,
            devnum: 3,
            speed: 12000000,
            vendorID: 0xABCD,
            productID: 0xEF01,
            deviceClass: 3,
            deviceSubClass: 1,
            deviceProtocol: 2,
            configurationCount: 1,
            configurationValue: 1,
            interfaceCount: 2
        )
        
        let response = DeviceListResponse(devices: [device1, device2])
        let encodedData = try response.encode()
        
        // Verify the encoded data has the correct length
        // 8 (header) + 4 (device count) + 4 (reserved) + 2 * 312 (devices) = 640 bytes
        XCTAssertEqual(encodedData.count, 640)
        
        // Verify the data can be decoded back correctly
        let decodedResponse = try DeviceListResponse.decode(from: encodedData)
        XCTAssertEqual(decodedResponse.deviceCount, 2)
        XCTAssertEqual(decodedResponse.devices.count, 2)
        XCTAssertEqual(decodedResponse.devices[0].busID, device1.busID)
        XCTAssertEqual(decodedResponse.devices[1].busID, device2.busID)
    }
    
    func testDeviceImportRequestEncoding() throws {
        // Test encoding a device import request
        let request = DeviceImportRequest(busID: "1-1")
        let encodedData = try request.encode()
        
        // Verify the encoded data has the correct length (8 + 32 = 40 bytes)
        XCTAssertEqual(encodedData.count, 40)
        
        // Verify the data can be decoded back correctly
        let decodedRequest = try DeviceImportRequest.decode(from: encodedData)
        XCTAssertEqual(decodedRequest.busID, request.busID)
        XCTAssertEqual(decodedRequest.header.command, .requestDeviceImport)
    }
    
    func testEndiannessHandling() throws {
        // Test that endianness conversion works correctly
        let originalValue16: UInt16 = 0x1234
        let originalValue32: UInt32 = 0x12345678
        
        // Convert to network byte order and back
        let networkValue16 = EndiannessConverter.toNetworkByteOrder(originalValue16)
        let networkValue32 = EndiannessConverter.toNetworkByteOrder(originalValue32)
        
        let restoredValue16 = EndiannessConverter.fromNetworkByteOrder(networkValue16)
        let restoredValue32 = EndiannessConverter.fromNetworkByteOrder(networkValue32)
        
        XCTAssertEqual(restoredValue16, originalValue16)
        XCTAssertEqual(restoredValue32, originalValue32)
    }
    
    func testStringEncodingUtilities() throws {
        // Test fixed-length string encoding
        let testString = "test-device"
        let encodedData = try StringEncodingUtilities.encodeFixedLengthString(testString, length: 32)
        
        XCTAssertEqual(encodedData.count, 32)
        
        // Verify the string can be decoded back correctly
        let decodedString = try StringEncodingUtilities.decodeFixedLengthString(from: encodedData, at: 0, length: 32)
        XCTAssertEqual(decodedString, testString)
    }
    
    func testMessageEncoder() throws {
        // Test the message encoder utility functions
        let devices = [
            USBIPExportedDevice(
                path: "/test/path",
                busID: "1-1",
                busnum: 1,
                devnum: 2,
                speed: 480000000,
                vendorID: 0x1234,
                productID: 0x5678,
                deviceClass: 9,
                deviceSubClass: 0,
                deviceProtocol: 1,
                configurationCount: 1,
                configurationValue: 1,
                interfaceCount: 1
            )
        ]
        
        // Test device list request encoding
        let deviceListRequestData = try USBIPMessageEncoder.encodeDeviceListRequest()
        XCTAssertEqual(deviceListRequestData.count, 8)
        
        // Test device list response encoding
        let deviceListResponseData = try USBIPMessageEncoder.encodeDeviceListResponse(devices: devices)
        XCTAssertEqual(deviceListResponseData.count, 328) // 8 + 4 + 4 + 312
        
        // Test device import request encoding
        let deviceImportRequestData = try USBIPMessageEncoder.encodeDeviceImportRequest(busID: "1-1")
        XCTAssertEqual(deviceImportRequestData.count, 40)
        
        // Test device import response encoding (success case)
        let deviceInfo = USBIPDeviceInfo(
            path: "/test/path",
            busID: "1-1",
            busnum: 1,
            devnum: 2,
            speed: 480000000,
            vendorID: 0x1234,
            productID: 0x5678,
            deviceClass: 9,
            deviceSubClass: 0,
            deviceProtocol: 1,
            configurationCount: 1,
            configurationValue: 1,
            interfaceCount: 1
        )
        
        let deviceImportResponseData = try USBIPMessageEncoder.encodeDeviceImportResponse(returnCode: 0)
        XCTAssertEqual(deviceImportResponseData.count, 12) // 8 + 4
        
        // Test device import response encoding (error case)
        let deviceImportErrorResponseData = try USBIPMessageEncoder.encodeDeviceImportResponse(returnCode: 1)
        XCTAssertEqual(deviceImportErrorResponseData.count, 12) // 8 + 4
    }
    
    // MARK: - Message Decoder Tests
    
    func testMessageDecoder() throws {
        // Test decoding device list request
        let deviceListRequestData = try USBIPMessageEncoder.encodeDeviceListRequest()
        let decodedRequest = try USBIPMessageDecoder.decodeDeviceListRequest(from: deviceListRequestData)
        XCTAssertEqual(decodedRequest.header.command, .requestDeviceList)
        
        // Test decoding device import request
        let deviceImportRequestData = try USBIPMessageEncoder.encodeDeviceImportRequest(busID: "1-1")
        let decodedImportRequest = try USBIPMessageDecoder.decodeDeviceImportRequest(from: deviceImportRequestData)
        XCTAssertEqual(decodedImportRequest.busID, "1-1")
        XCTAssertEqual(decodedImportRequest.header.command, .requestDeviceImport)
    }
    
    func testGenericMessageDecoding() throws {
        // Test generic message decoding based on command type
        let deviceListRequestData = try USBIPMessageEncoder.encodeDeviceListRequest()
        let decodedMessage = try USBIPMessageDecoder.decodeMessage(from: deviceListRequestData)
        
        XCTAssertTrue(decodedMessage is DeviceListRequest)
        if let request = decodedMessage as? DeviceListRequest {
            XCTAssertEqual(request.header.command, .requestDeviceList)
        }
        
        // Test with device import request
        let deviceImportRequestData = try USBIPMessageEncoder.encodeDeviceImportRequest(busID: "test-device")
        let decodedImportMessage = try USBIPMessageDecoder.decodeMessage(from: deviceImportRequestData)
        
        XCTAssertTrue(decodedImportMessage is DeviceImportRequest)
        if let importRequest = decodedImportMessage as? DeviceImportRequest {
            XCTAssertEqual(importRequest.header.command, .requestDeviceImport)
            XCTAssertEqual(importRequest.busID, "test-device")
        }
    }
    
    func testHeaderValidation() throws {
        // Test valid header validation
        let validData = try USBIPMessageEncoder.encodeDeviceListRequest()
        let header = try USBIPMessageDecoder.validateHeader(in: validData)
        XCTAssertEqual(header.version, USBIPProtocol.version)
        XCTAssertEqual(header.command, .requestDeviceList)
        
        // Test command peeking
        let command = try USBIPMessageDecoder.peekCommand(in: validData)
        XCTAssertEqual(command, .requestDeviceList)
    }
    
    func testMessageIntegrityValidation() throws {
        // Test with valid message
        let validData = try USBIPMessageEncoder.encodeDeviceListRequest()
        let isValid = try USBIPMessageDecoder.validateMessageIntegrity(data: validData)
        XCTAssertTrue(isValid)
        
        // Test with complex message
        let devices = [
            USBIPExportedDevice(
                path: "/test/path",
                busID: "1-1",
                busnum: 1,
                devnum: 2,
                speed: 480000000,
                vendorID: 0x1234,
                productID: 0x5678,
                deviceClass: 9,
                deviceSubClass: 0,
                deviceProtocol: 1,
                configurationCount: 1,
                configurationValue: 1,
                interfaceCount: 1
            )
        ]
        
        let complexData = try USBIPMessageEncoder.encodeDeviceListResponse(devices: devices)
        let isComplexValid = try USBIPMessageDecoder.validateMessageIntegrity(data: complexData)
        XCTAssertTrue(isComplexValid)
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidDataLengthHandling() throws {
        // Test with insufficient data for header
        let shortData = Data([0x01, 0x11, 0x80])
        
        XCTAssertThrowsError(try USBIPMessageDecoder.validateHeader(in: shortData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
            if case USBIPProtocolError.invalidDataLength = error {
                // Expected error
            } else {
                XCTFail("Expected invalidDataLength error")
            }
        }
        
        XCTAssertThrowsError(try USBIPMessageDecoder.decodeMessage(from: shortData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
            if case USBIPProtocolError.invalidDataLength = error {
                // Expected error
            } else {
                XCTFail("Expected invalidDataLength error")
            }
        }
    }
    
    func testUnsupportedVersionHandling() throws {
        // Create data with invalid version
        var invalidVersionData = Data()
        invalidVersionData.append(EndiannessConverter.writeUInt16ToData(0x0200)) // Invalid version
        invalidVersionData.append(EndiannessConverter.writeUInt16ToData(USBIPProtocol.Command.requestDeviceList.rawValue))
        invalidVersionData.append(EndiannessConverter.writeUInt32ToData(0)) // Status
        
        XCTAssertThrowsError(try USBIPMessageDecoder.validateHeader(in: invalidVersionData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
            if case USBIPProtocolError.unsupportedVersion(let version) = error {
                XCTAssertEqual(version, 0x0200)
            } else {
                XCTFail("Expected unsupportedVersion error")
            }
        }
        
        XCTAssertThrowsError(try USBIPMessageDecoder.decodeMessage(from: invalidVersionData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
            if case USBIPProtocolError.unsupportedVersion = error {
                // Expected error
            } else {
                XCTFail("Expected unsupportedVersion error")
            }
        }
    }
    
    func testUnsupportedCommandHandling() throws {
        // Create data with invalid command
        var invalidCommandData = Data()
        invalidCommandData.append(EndiannessConverter.writeUInt16ToData(USBIPProtocol.version))
        invalidCommandData.append(EndiannessConverter.writeUInt16ToData(0x9999)) // Invalid command
        invalidCommandData.append(EndiannessConverter.writeUInt32ToData(0)) // Status
        
        XCTAssertThrowsError(try USBIPMessageDecoder.peekCommand(in: invalidCommandData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
            if case USBIPProtocolError.unsupportedCommand(let command) = error {
                XCTAssertEqual(command, 0x9999)
            } else {
                XCTFail("Expected unsupportedCommand error")
            }
        }
    }
    
    func testInvalidMessageFormatHandling() throws {
        // Test device list request with wrong length
        var invalidLengthData = try USBIPMessageEncoder.encodeDeviceListRequest()
        invalidLengthData.append(0xFF) // Add extra byte
        
        XCTAssertThrowsError(try USBIPMessageDecoder.decodeDeviceListRequest(from: invalidLengthData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
            if case USBIPProtocolError.invalidMessageFormat = error {
                // Expected error
            } else {
                XCTFail("Expected invalidMessageFormat error")
            }
        }
        
        // Test device import request with wrong length
        var invalidImportData = try USBIPMessageEncoder.encodeDeviceImportRequest(busID: "1-1")
        invalidImportData.append(0xFF) // Add extra byte
        
        XCTAssertThrowsError(try USBIPMessageDecoder.decodeDeviceImportRequest(from: invalidImportData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
            if case USBIPProtocolError.invalidMessageFormat = error {
                // Expected error
            } else {
                XCTFail("Expected invalidMessageFormat error")
            }
        }
    }
    
    func testMalformedMessageHandling() throws {
        // Test with completely invalid data
        let malformedData = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        
        XCTAssertThrowsError(try USBIPMessageDecoder.decodeMessage(from: malformedData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
            // Should throw either unsupportedVersion or unsupportedCommand
        }
        
        // Test message integrity with malformed data
        let isValid = try USBIPMessageDecoder.validateMessageIntegrity(data: malformedData)
        XCTAssertFalse(isValid)
    }
    
    func testDeviceImportResponseDecoding() throws {
        // Test successful device import response
        let successResponseData = try USBIPMessageEncoder.encodeDeviceImportResponse(returnCode: 0)
        let decodedSuccessResponse = try USBIPMessageDecoder.decodeDeviceImportResponse(from: successResponseData)
        XCTAssertEqual(decodedSuccessResponse.returnCode, 0)
        
        // Test error device import response
        let errorResponseData = try USBIPMessageEncoder.encodeDeviceImportResponse(returnCode: 1)
        let decodedErrorResponse = try USBIPMessageDecoder.decodeDeviceImportResponse(from: errorResponseData)
        XCTAssertEqual(decodedErrorResponse.returnCode, 1)
        
        // Test invalid length for device import response
        let invalidLengthData = Data(count: 20) // Invalid length
        XCTAssertThrowsError(try USBIPMessageDecoder.decodeDeviceImportResponse(from: invalidLengthData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
            if case USBIPProtocolError.invalidMessageFormat = error {
                // Expected error
            } else {
                XCTFail("Expected invalidMessageFormat error")
            }
        }
    }
}