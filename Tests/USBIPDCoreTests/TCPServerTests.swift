// TCPServerTests.swift
// Tests for TCP server implementation

import XCTest
import Network
@testable import USBIPDCore
@testable import Common

final class TCPServerTests: XCTestCase {
    var server: TCPServer!
    
    override func setUp() {
        super.setUp()
        server = TCPServer()
    }
    
    override func tearDown() {
        if server.isRunning() {
            try? server.stop()
        }
        server = nil
        super.tearDown()
    }
    
    func testServerStartStop() throws {
        // Test initial state
        XCTAssertFalse(server.isRunning())
        
        // Test starting server with random port to avoid conflicts
        let port = UInt16.random(in: 8000...9000)
        try server.start(port: port)
        XCTAssertTrue(server.isRunning())
        
        // Test stopping server
        try server.stop()
        XCTAssertFalse(server.isRunning())
    }
    
    func testServerAlreadyRunningError() throws {
        let port = UInt16.random(in: 8000...9000)
        try server.start(port: port)
        
        // Should throw error when trying to start again
        XCTAssertThrowsError(try server.start(port: port)) { error in
            XCTAssertTrue(error is ServerError)
            if case ServerError.alreadyRunning = error {
                // Expected error
            } else {
                XCTFail("Expected ServerError.alreadyRunning")
            }
        }
    }
    
    func testServerNotRunningError() throws {
        // Should throw error when trying to stop a server that's not running
        XCTAssertThrowsError(try server.stop()) { error in
            XCTAssertTrue(error is ServerError)
            if case ServerError.notRunning = error {
                // Expected error
            } else {
                XCTFail("Expected ServerError.notRunning")
            }
        }
    }
    
    func testInvalidPortError() throws {
        // Test with invalid port number (0 is invalid)
        XCTAssertThrowsError(try server.start(port: 0)) { error in
            XCTAssertTrue(error is NetworkError)
            if case NetworkError.bindFailed = error {
                // Expected error
            } else {
                XCTFail("Expected NetworkError.bindFailed")
            }
        }
    }
    
    func testClientConnectionCallback() throws {
        let expectation = XCTestExpectation(description: "Client connection callback")
        
        server.onClientConnected = { connection in
            XCTAssertNotNil(connection.id)
            expectation.fulfill()
        }
        
        let port = UInt16.random(in: 8000...9000)
        try server.start(port: port)
        
        // Create a test client connection
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(integerLiteral: port), using: .tcp)
        connection.start(queue: DispatchQueue.global())
        
        wait(for: [expectation], timeout: 2.0)
        
        connection.cancel()
    }
    
    func testClientDisconnectionCallback() throws {
        let connectionExpectation = XCTestExpectation(description: "Client connection callback")
        let disconnectionExpectation = XCTestExpectation(description: "Client disconnection callback")
        
        var clientConnection: ClientConnection?
        
        server.onClientConnected = { connection in
            clientConnection = connection
            connectionExpectation.fulfill()
        }
        
        server.onClientDisconnected = { connection in
            XCTAssertEqual(connection.id, clientConnection?.id)
            disconnectionExpectation.fulfill()
        }
        
        let port = UInt16.random(in: 8000...9000)
        try server.start(port: port)
        
        // Create a test client connection
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(integerLiteral: port), using: .tcp)
        connection.start(queue: DispatchQueue.global())
        
        wait(for: [connectionExpectation], timeout: 2.0)
        
        // Disconnect the client
        connection.cancel()
        
        wait(for: [disconnectionExpectation], timeout: 2.0)
    }
    
    func testDataSendingAndReceiving() throws {
        let connectionExpectation = XCTestExpectation(description: "Client connection")
        let dataReceivedExpectation = XCTestExpectation(description: "Data received")
        
        let testData = "Hello, USB/IP!".data(using: .utf8)!
        
        server.onClientConnected = { connection in
            // Cast to concrete type to access mutable properties
            if let tcpConnection = connection as? TCPClientConnection {
                tcpConnection.onDataReceived = { data in
                    XCTAssertEqual(data, testData)
                    dataReceivedExpectation.fulfill()
                }
            }
            connectionExpectation.fulfill()
        }
        
        let port = UInt16.random(in: 8000...9000)
        try server.start(port: port)
        
        // Create a test client connection
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(integerLiteral: port), using: .tcp)
        connection.start(queue: DispatchQueue.global())
        
        wait(for: [connectionExpectation], timeout: 2.0)
        
        // Send data from client to server
        connection.send(content: testData, completion: .contentProcessed { error in
            XCTAssertNil(error)
        })
        
        wait(for: [dataReceivedExpectation], timeout: 2.0)
        
        connection.cancel()
    }
    
    func testConnectionErrorHandling() throws {
        let connectionExpectation = XCTestExpectation(description: "Client connection")
        
        var clientConnection: ClientConnection?
        
        server.onClientConnected = { connection in
            clientConnection = connection
            connectionExpectation.fulfill()
        }
        
        let port = UInt16.random(in: 8000...9000)
        try server.start(port: port)
        
        // Create a test client connection
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(integerLiteral: port), using: .tcp)
        connection.start(queue: DispatchQueue.global())
        
        wait(for: [connectionExpectation], timeout: 2.0)
        
        // Try to send data after closing the connection to trigger an error
        try? clientConnection?.close()
        
        // Attempt to send data on closed connection should trigger error
        XCTAssertThrowsError(try clientConnection?.send(data: Data("test".utf8))) { error in
            XCTAssertTrue(error is NetworkError)
            if case NetworkError.connectionClosed = error {
                // Expected error
            } else {
                XCTFail("Expected NetworkError.connectionClosed")
            }
        }
        
        connection.cancel()
    }
}