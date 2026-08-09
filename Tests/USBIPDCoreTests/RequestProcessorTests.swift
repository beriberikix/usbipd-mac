// RequestProcessorTests.swift
// Tests for the RequestProcessor class

import XCTest
@testable import USBIPDCore
import Common

class RequestProcessorTests: XCTestCase {
    
    // Mock DeviceDiscovery for testing
    class MockDeviceDiscovery: DeviceDiscovery {
        var devices: [USBDevice] = []
        var discoverDevicesCalled = false
        var getDeviceCalled = false
        var startNotificationsCalled = false
        var stopNotificationsCalled = false
        var requestedBusID: String?
        var requestedDeviceID: String?
        
        var onDeviceConnected: ((USBDevice) -> Void)?
        var onDeviceDisconnected: ((USBDevice) -> Void)?
        
        func discoverDevices() throws -> [USBDevice] {
            discoverDevicesCalled = true
            return devices
        }
        
        func getDevice(busID: String, deviceID: String) throws -> USBDevice? {
            getDeviceCalled = true
            requestedBusID = busID
            requestedDeviceID = deviceID
            
            return devices.first { $0.busID == busID && $0.deviceID == deviceID }
        }
        
        func startNotifications() throws {
            startNotificationsCalled = true
        }
        
        func stopNotifications() {
            stopNotificationsCalled = true
        }
    }
    
    // Create a sample USB device for testing
    func createSampleDevice() -> USBDevice {
        // IOKitDeviceDiscovery.generateDeviceIDs returns the bus number and device
        // number separately — "1" and "17" for the J-Link on a real host — not an
        // already-composed "1-1". The fixture used the composed form, which hid that
        // the exported busid needs building from both parts.
        return USBDevice(
            busID: "1",
            deviceID: "17",
            vendorID: 0x1234,
            productID: 0x5678,
            deviceClass: 0x09,
            deviceSubClass: 0x00,
            deviceProtocol: 0x00,
            speed: .high,
            manufacturerString: "Test Manufacturer",
            productString: "Test Device",
            serialNumberString: "123456789"
        )
    }
    
    // Create a device list request for testing
    func createDeviceListRequest() -> Data {
        let header = USBIPHeader(command: .requestDeviceList)
        let request = DeviceListRequest(header: header)
        return try! USBIPMessageEncoder.encode(request)
    }
    
    // Create a device import request for testing
    func createDeviceImportRequest(busID: String) -> Data {
        let header = USBIPHeader(command: .requestDeviceImport)
        let request = DeviceImportRequest(header: header, busID: busID)
        return try! USBIPMessageEncoder.encode(request)
    }
    
    func testProcessDeviceListRequest() throws {
        // Arrange
        let deviceDiscovery = MockDeviceDiscovery()
        let device = createSampleDevice()
        deviceDiscovery.devices = [device]
        
        let mockDeviceClaimManager = UserspaceDeviceClaimManager()
        let processor = RequestProcessor(deviceDiscovery: deviceDiscovery, deviceClaimManager: mockDeviceClaimManager)
        let requestData = createDeviceListRequest()
        
        // Act
        let responseData = try processor.processRequest(requestData)
        
        // Assert
        XCTAssertTrue(deviceDiscovery.discoverDevicesCalled, "Device discovery should be called")
        
        // Decode the response to verify it
        let response = try USBIPMessageDecoder.decodeDeviceListResponse(from: responseData)
        XCTAssertEqual(response.header.command, USBIPProtocol.Command.replyDeviceList, "Response should be a device list reply")
        XCTAssertEqual(response.header.status, 0, "Status should be success (0)")
        XCTAssertEqual(response.deviceCount, 1, "Response should contain 1 device")
        XCTAssertEqual(response.devices.count, 1, "Response should contain 1 device")
        
        // Verify device details
        let exportedDevice = response.devices[0]
        // The advertised busid is the composed bus-device identifier a client passes
        // back to `usbip attach`.
        XCTAssertEqual(exportedDevice.busID, "\(device.busID)-\(device.deviceID)",
                       "Exported busid should be the composed bus-device identifier")
        XCTAssertEqual(exportedDevice.vendorID, device.vendorID, "Vendor ID should match")
        XCTAssertEqual(exportedDevice.productID, device.productID, "Product ID should match")
        XCTAssertEqual(exportedDevice.deviceClass, device.deviceClass, "Device class should match")
    }
    
    // MARK: - Bind Allow-List Enforcement

    // The allow-list was written to config by `bind` and then consulted by nothing, so
    // the server advertised and served every USB device on the machine no matter what
    // was bound. These cover both points where sharing is now decided.

    func testDeviceListOmitsUnboundDevices() throws {
        let deviceDiscovery = MockDeviceDiscovery()
        let device = createSampleDevice()
        deviceDiscovery.devices = [device]

        let processor = RequestProcessor(
            deviceDiscovery: deviceDiscovery,
            deviceClaimManager: UserspaceDeviceClaimManager(),
            boundDevices: temporaryStore(binding: [])
        )

        let responseData = try processor.processRequest(createDeviceListRequest())
        let response = try USBIPMessageDecoder.decodeDeviceListResponse(from: responseData)

        XCTAssertEqual(response.deviceCount, 0, "An unbound device must not be advertised")
        XCTAssertEqual(response.devices.count, 0, "An unbound device must not be advertised")
    }

    func testDeviceListIncludesBoundDevices() throws {
        let deviceDiscovery = MockDeviceDiscovery()
        let device = createSampleDevice()
        deviceDiscovery.devices = [device]

        let processor = RequestProcessor(
            deviceDiscovery: deviceDiscovery,
            deviceClaimManager: UserspaceDeviceClaimManager(),
            boundDevices: temporaryStore(binding: ["\(device.busID)-\(device.deviceID)"])
        )

        let responseData = try processor.processRequest(createDeviceListRequest())
        let response = try USBIPMessageDecoder.decodeDeviceListResponse(from: responseData)

        XCTAssertEqual(response.deviceCount, 1, "A bound device should be advertised")
    }

    func testImportRefusesUnboundDevice() throws {
        let deviceDiscovery = MockDeviceDiscovery()
        let device = createSampleDevice()
        deviceDiscovery.devices = [device]

        let processor = RequestProcessor(
            deviceDiscovery: deviceDiscovery,
            deviceClaimManager: UserspaceDeviceClaimManager(),
            boundDevices: temporaryStore(binding: [])
        )

        // Absent from the list, so a client that guesses the busid must still be refused.
        let busID = "\(device.busID)-\(device.deviceID)"
        let responseData = try processor.processRequest(createDeviceImportRequest(busID: busID))
        let response = try USBIPMessageDecoder.decodeDeviceImportResponse(from: responseData)

        XCTAssertNotEqual(response.header.status, 0, "Importing an unbound device must fail")
    }

    func testProcessDeviceListRequestWithNoDevices() throws {
        // Arrange
        let deviceDiscovery = MockDeviceDiscovery()
        deviceDiscovery.devices = []
        
        let mockDeviceClaimManager = UserspaceDeviceClaimManager()
        let processor = RequestProcessor(deviceDiscovery: deviceDiscovery, deviceClaimManager: mockDeviceClaimManager)
        let requestData = createDeviceListRequest()
        
        // Act
        let responseData = try processor.processRequest(requestData)
        
        // Assert
        XCTAssertTrue(deviceDiscovery.discoverDevicesCalled, "Device discovery should be called")
        
        // Decode the response to verify it
        let response = try USBIPMessageDecoder.decodeDeviceListResponse(from: responseData)
        XCTAssertEqual(response.header.command, USBIPProtocol.Command.replyDeviceList, "Response should be a device list reply")
        XCTAssertEqual(response.header.status, 0, "Status should be success (0)")
        XCTAssertEqual(response.deviceCount, 0, "Response should contain 0 devices")
        XCTAssertEqual(response.devices.count, 0, "Response should contain 0 devices")
    }
    
    func testProcessDeviceImportRequest() throws {
        // Arrange
        let deviceDiscovery = MockDeviceDiscovery()
        let device = createSampleDevice()
        deviceDiscovery.devices = [device]
        
        let mockDeviceClaimManager = UserspaceDeviceClaimManager()
        let processor = RequestProcessor(deviceDiscovery: deviceDiscovery, deviceClaimManager: mockDeviceClaimManager)
        let requestData = createDeviceImportRequest(busID: "1-17")
        
        // Act
        let responseData = try processor.processRequest(requestData)
        
        // Assert
        XCTAssertTrue(deviceDiscovery.getDeviceCalled, "Device discovery getDevice should be called")
        // "1-17" splits into bus 1, device 17 — the same pair generateDeviceIDs
        // produces from a locationID, and the pair getDevice expects.
        XCTAssertEqual(deviceDiscovery.requestedBusID, "1", "Bus number should be extracted")
        XCTAssertEqual(deviceDiscovery.requestedDeviceID, "17", "Device number should be extracted")
        
        // Decode the response to verify it
        let response = try USBIPMessageDecoder.decodeDeviceImportResponse(from: responseData)
        XCTAssertEqual(response.header.command, USBIPProtocol.Command.replyDeviceImport, "Response should be a device import reply")
        XCTAssertEqual(response.header.status, 0, "Status should be success (0)")
        XCTAssertEqual(response.header.status, 0, "Status should be success (0)")
    }
    
    func testProcessDeviceImportRequestDeviceNotFound() throws {
        // Arrange
        let deviceDiscovery = MockDeviceDiscovery()
        deviceDiscovery.devices = [] // No devices available
        
        let mockDeviceClaimManager = UserspaceDeviceClaimManager()
        let processor = RequestProcessor(deviceDiscovery: deviceDiscovery, deviceClaimManager: mockDeviceClaimManager)
        let requestData = createDeviceImportRequest(busID: "1-17")
        
        // Act
        let responseData = try processor.processRequest(requestData)
        
        // Assert
        XCTAssertTrue(deviceDiscovery.getDeviceCalled, "Device discovery getDevice should be called")
        
        // Decode the response to verify it
        let response = try USBIPMessageDecoder.decodeDeviceImportResponse(from: responseData)
        XCTAssertEqual(response.header.command, USBIPProtocol.Command.replyDeviceImport, "Response should be a device import reply")
        XCTAssertEqual(response.header.status, 1, "Status should be error (1)")
    }
    
    func testProcessInvalidRequest() throws {
        // Arrange
        let deviceDiscovery = MockDeviceDiscovery()
        let mockDeviceClaimManager = UserspaceDeviceClaimManager()
        let processor = RequestProcessor(deviceDiscovery: deviceDiscovery, deviceClaimManager: mockDeviceClaimManager)
        
        // Create an invalid request with incorrect data
        let invalidData = Data([0x01, 0x02, 0x03, 0x04])
        
        // Act & Assert
        XCTAssertThrowsError(try processor.processRequest(invalidData), "Processing invalid data should throw an error")
    }
    
    func testProcessUnsupportedCommand() throws {
        // Arrange
        let deviceDiscovery = MockDeviceDiscovery()
        let mockDeviceClaimManager = UserspaceDeviceClaimManager()
        let processor = RequestProcessor(deviceDiscovery: deviceDiscovery, deviceClaimManager: mockDeviceClaimManager)
        
        // Create a reply message (which should not be processed as a request)
        let header = USBIPHeader(command: .replyDeviceList)
        let data = try USBIPMessageEncoder.encode(header)
        
        // Act & Assert
        XCTAssertThrowsError(try processor.processRequest(data), "Processing unsupported command should throw an error")
    }

    // MARK: - The bound list is written by another process

    /// A store backed by a file of its own, removed when the test ends.
    private func temporaryStore(binding devices: [String]) -> BoundDeviceStore {
        let path = NSTemporaryDirectory() + "usbipd-bound-\(UUID().uuidString).json"
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + ".lock")
        }
        let store = BoundDeviceStore(path: path)
        for device in devices {
            _ = try? store.bind(device)
        }
        return store
    }

    /// `usbipd bind` writes the bound-device list and exits; the daemon is a separate,
    /// long-running process. It read that state once at startup and never again, so a
    /// device bound while the daemon was running stayed unimportable — `usbip attach`
    /// answered "Request Failed" — until the daemon was restarted, which nothing told
    /// the user to do.
    func testBindingWhileRunningTakesEffectWithoutARestart() throws {
        let deviceDiscovery = MockDeviceDiscovery()
        let device = createSampleDevice()
        deviceDiscovery.devices = [device]
        let busid = "\(device.busID)-\(device.deviceID)"

        let store = temporaryStore(binding: [])
        let processor = RequestProcessor(
            deviceDiscovery: deviceDiscovery,
            deviceClaimManager: UserspaceDeviceClaimManager(),
            boundDevices: store
        )

        var response = try USBIPMessageDecoder.decodeDeviceListResponse(
            from: try processor.processRequest(createDeviceListRequest()))
        XCTAssertEqual(response.deviceCount, 0, "nothing is bound yet")

        // What `bind` does, from its own process.
        try store.bind(busid)
        try touch(store)

        response = try USBIPMessageDecoder.decodeDeviceListResponse(
            from: try processor.processRequest(createDeviceListRequest()))
        XCTAssertEqual(response.deviceCount, 1, "a device bound while running should be served")
    }

    /// And the reverse, so the reload cannot pass by only ever adding devices.
    func testUnbindingWhileRunningTakesEffectWithoutARestart() throws {
        let deviceDiscovery = MockDeviceDiscovery()
        let device = createSampleDevice()
        deviceDiscovery.devices = [device]
        let busid = "\(device.busID)-\(device.deviceID)"

        let store = temporaryStore(binding: [busid])
        let processor = RequestProcessor(
            deviceDiscovery: deviceDiscovery,
            deviceClaimManager: UserspaceDeviceClaimManager(),
            boundDevices: store
        )

        var response = try USBIPMessageDecoder.decodeDeviceListResponse(
            from: try processor.processRequest(createDeviceListRequest()))
        XCTAssertEqual(response.deviceCount, 1, "bound at startup")

        try store.unbind(busid)
        try touch(store)

        response = try USBIPMessageDecoder.decodeDeviceListResponse(
            from: try processor.processRequest(createDeviceListRequest()))
        XCTAssertEqual(response.deviceCount, 0, "an unbound device should stop being served")
    }

    /// Modification times have to differ for a change to be noticed, and a test can
    /// write twice inside one filesystem timestamp tick.
    private func touch(_ store: BoundDeviceStore) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(1)], ofItemAtPath: store.filePath)
    }
}
