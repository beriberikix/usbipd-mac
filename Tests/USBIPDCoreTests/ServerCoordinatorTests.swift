// ServerCoordinatorTests.swift
// Tests for the ServerCoordinator class

import XCTest
@testable import USBIPDCore
import Common

class ServerCoordinatorTests: XCTestCase {
    
    // Mock NetworkService for testing
    class MockNetworkService: NetworkService {
        var startCalled = false
        var stopCalled = false
        var isRunningValue = false
        var startError: Error?
        var stopError: Error?
        var port: Int?
        
        var onClientConnected: ((ClientConnection) -> Void)?
        var onClientDisconnected: ((ClientConnection) -> Void)?
        
        func start(port: Int) throws {
            self.port = port
            startCalled = true
            if let error = startError {
                throw error
            }
            isRunningValue = true
        }
        
        func stop() throws {
            stopCalled = true
            if let error = stopError {
                throw error
            }
            isRunningValue = false
        }
        
        func isRunning() -> Bool {
            return isRunningValue
        }
    }
    
    // Mock DeviceDiscovery for testing
    class MockDeviceDiscovery: DeviceDiscovery {
        var discoverDevicesCalled = false
        var getDeviceCalled = false
        var startNotificationsCalled = false
        var stopNotificationsCalled = false
        var startError: Error?
        
        var onDeviceConnected: ((USBDevice) -> Void)?
        var onDeviceDisconnected: ((USBDevice) -> Void)?
        
        func discoverDevices() throws -> [USBDevice] {
            discoverDevicesCalled = true
            return []
        }
        
        func getDevice(busID: String, deviceID: String) throws -> USBDevice? {
            getDeviceCalled = true
            return nil
        }
        
        func startNotifications() throws {
            startNotificationsCalled = true
            if let error = startError {
                throw error
            }
        }
        
        func stopNotifications() {
            stopNotificationsCalled = true
        }
    }
    
    // Mock ClientConnection for testing
    class MockClientConnection: ClientConnection {
        let id = UUID()
        var sendCalled = false
        var closeCalled = false
        var sentData: Data?
        var sendError: Error?
        
        var onDataReceived: ((Data) -> Void)?
        var onError: ((Error) -> Void)?
        
        func send(data: Data) throws {
            sendCalled = true
            sentData = data
            if let error = sendError {
                throw error
            }
        }
        
        func close() throws {
            closeCalled = true
        }
    }
    
    func testServerStartStop() throws {
        // Arrange
        let networkService = MockNetworkService()
        let deviceDiscovery = MockDeviceDiscovery()
        let server = ServerCoordinator(networkService: networkService, deviceDiscovery: deviceDiscovery)
        
        // Act & Assert - Start
        try server.start()
        XCTAssertTrue(networkService.startCalled, "Network service start should be called")
        XCTAssertEqual(networkService.port, ServerConfig.defaultPort, "Server should use default port")
        XCTAssertTrue(deviceDiscovery.startNotificationsCalled, "Device discovery notifications should be started")
        XCTAssertTrue(server.isRunning(), "Server should be running")
        
        // Act & Assert - Stop
        try server.stop()
        XCTAssertTrue(networkService.stopCalled, "Network service stop should be called")
        XCTAssertTrue(deviceDiscovery.stopNotificationsCalled, "Device discovery notifications should be stopped")
        XCTAssertFalse(server.isRunning(), "Server should not be running")
    }
    
    func testServerStartWithCustomPort() throws {
        // Arrange
        let networkService = MockNetworkService()
        let deviceDiscovery = MockDeviceDiscovery()
        let customPort = 8000
        let config = ServerConfig(port: customPort)
        let server = ServerCoordinator(networkService: networkService, deviceDiscovery: deviceDiscovery, config: config)
        
        // Act
        try server.start()
        
        // Assert
        XCTAssertEqual(networkService.port, customPort, "Server should use custom port")
    }
    
    func testServerStartAlreadyRunning() throws {
        // Arrange
        let networkService = MockNetworkService()
        let deviceDiscovery = MockDeviceDiscovery()
        let server = ServerCoordinator(networkService: networkService, deviceDiscovery: deviceDiscovery)
        
        // Act & Assert
        try server.start()
        XCTAssertThrowsError(try server.start(), "Starting an already running server should throw an error")
    }
    
    func testServerStopNotRunning() throws {
        // Arrange
        let networkService = MockNetworkService()
        let deviceDiscovery = MockDeviceDiscovery()
        let server = ServerCoordinator(networkService: networkService, deviceDiscovery: deviceDiscovery)
        
        // Act & Assert
        XCTAssertThrowsError(try server.stop(), "Stopping a server that is not running should throw an error")
    }
    
    func testServerStartNetworkServiceFailure() throws {
        // Arrange
        let networkService = MockNetworkService()
        networkService.startError = NetworkError.bindFailed("Test error")
        let deviceDiscovery = MockDeviceDiscovery()
        let server = ServerCoordinator(networkService: networkService, deviceDiscovery: deviceDiscovery)
        
        // Act & Assert
        XCTAssertThrowsError(try server.start(), "Server start should throw when network service fails")
        XCTAssertFalse(server.isRunning(), "Server should not be running when start fails")
    }
    
    func testServerStartDeviceDiscoveryFailure() throws {
        // Arrange
        let networkService = MockNetworkService()
        let deviceDiscovery = MockDeviceDiscovery()
        deviceDiscovery.startError = DeviceError.ioKitError(0, "Test error")
        let server = ServerCoordinator(networkService: networkService, deviceDiscovery: deviceDiscovery)
        
        // Act & Assert
        XCTAssertThrowsError(try server.start(), "Server start should throw when device discovery fails")
        XCTAssertFalse(server.isRunning(), "Server should not be running when start fails")
    }
    
    func testClientConnectionCallbacks() throws {
        // Arrange
        let networkService = MockNetworkService()
        let deviceDiscovery = MockDeviceDiscovery()
        let server = ServerCoordinator(networkService: networkService, deviceDiscovery: deviceDiscovery)
        let clientConnection = MockClientConnection()
        var errorReceived = false
        
        server.onError = { _ in
            errorReceived = true
        }
        
        // Start the server
        try server.start()
        
        // Act - Simulate client connection
        networkService.onClientConnected?(clientConnection)
        
        // Simulate client sending data
        let testData = Data([0x01, 0x02, 0x03])
        clientConnection.onDataReceived?(testData)
        
        // Simulate client error
        clientConnection.onError?(NetworkError.connectionFailed("Test error"))
        
        // Assert
        XCTAssertTrue(errorReceived, "Server should forward client connection errors")
    }
}