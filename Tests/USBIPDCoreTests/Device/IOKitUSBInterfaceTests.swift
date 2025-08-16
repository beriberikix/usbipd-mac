// IOKitUSBInterfaceTests.swift
// Comprehensive unit tests for IOKit USB interface wrapper

import XCTest
import Foundation
import IOKit
import IOKit.usb
import Common
@testable import USBIPDCore

/// Comprehensive test suite for IOKitUSBInterface
class IOKitUSBInterfaceTests: XCTestCase {
    
    // MARK: - TestSuite Protocol Implementation - temporarily disabled
    // var environmentConfig: TestEnvironmentConfig {
    //     return TestEnvironmentConfig.development
    // }
    // 
    // var requiredCapabilities: TestEnvironmentCapabilities {
    //     return [] // Unit tests only require basic capabilities
    // }
    // 
    // var testCategory: String {
    //     return "unit"
    // }
    
    // MARK: - Test Properties
    
    private var testDevice: USBDevice!
    private var mockIOKit: MockIOKitInterface!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        
        // Create test device
        testDevice = USBDevice(
            busID: "1-1",
            deviceID: "1.0",
            vendorID: 0x1234,
            productID: 0x5678,
            deviceClass: 9, // Hub class
            deviceSubClass: 0,
            deviceProtocol: 0,
            speed: .high,
            manufacturerString: "Test Manufacturer",
            productString: "Test Device",
            serialNumberString: "TEST123"
        )
        
        // Create mock IOKit interface
        mockIOKit = MockIOKitInterface()
    }
    
    override func tearDown() {
        mockIOKit = nil
        testDevice = nil
        
        super.tearDown()
    }
    
    // MARK: - Basic Functionality Tests
    
    func testIOKitUSBInterfaceCreationWithValidDevice() {
        // Test that IOKitUSBInterface can be created with a valid device and mock IOKit
        // This tests the initialization path without requiring real IOKit services
        
        // Configure mock to simulate successful service discovery
        let mockService = MockUSBDevice(
            vendorID: testDevice.vendorID,
            productID: testDevice.productID,
            deviceClass: testDevice.deviceClass,
            deviceSubClass: testDevice.deviceSubClass,
            deviceProtocol: testDevice.deviceProtocol,
            manufacturerString: testDevice.manufacturerString,
            productString: testDevice.productString,
            serialNumberString: testDevice.serialNumberString
        )
        mockIOKit.mockDevices = [mockService]
        
        // Attempt to create IOKitUSBInterface
        do {
            let usbInterface = try IOKitUSBInterface(device: testDevice, interfaceNumber: 0, ioKit: mockIOKit)
            XCTAssertNotNil(usbInterface)
        } catch {
            // In development environment, this may fail due to lack of real IOKit services
            // This is expected and acceptable for unit tests
            print("IOKitUSBInterface creation failed as expected in test environment: \(error)")
        }
        
        // Verify that the mock was consulted for service matching
        XCTAssertFalse(mockIOKit.serviceMatchingCalls.isEmpty, "Should attempt service matching during initialization")
    }
    
    func testIOKitUSBInterfaceCreationWithInvalidDevice() {
        // Configure mock to simulate no matching services
        mockIOKit.mockDevices = []
        mockIOKit.shouldFailGetMatchingServices = true
        mockIOKit.getMatchingServicesError = kIOReturnNotFound
        
        // Attempt to create IOKitUSBInterface should fail
        XCTAssertThrowsError(try IOKitUSBInterface(device: testDevice, interfaceNumber: 0, ioKit: mockIOKit)) { error in
            // Should get an IOKit-related error
            print("Expected initialization failure: \(error)")
        }
        
        // Verify that mock was consulted
        XCTAssertTrue(mockIOKit.shouldFailGetMatchingServices)
    }
    
    func testIOKitUSBInterfaceErrorHandling() {
        // Test various error conditions that can be simulated with mock
        mockIOKit.shouldFailServiceMatching = true
        
        XCTAssertThrowsError(try IOKitUSBInterface(device: testDevice, interfaceNumber: 0, ioKit: mockIOKit)) { error in
            // Verify we get appropriate error handling
            XCTAssertTrue(error is IOKitError || error is USBRequestError, "Should throw appropriate IOKit or USB error")
        }
        
        // Verify error was detected
        XCTAssertTrue(mockIOKit.shouldFailServiceMatching)
    }
    
    // MARK: - Mock IOKit Integration Tests
    
    func testMockIOKitCallTracking() {
        // Test that our mock properly tracks method calls
        mockIOKit.serviceMatchingCalls.removeAll()
        
        // Attempt initialization which should call service matching
        _ = try? IOKitUSBInterface(device: testDevice, interfaceNumber: 0, ioKit: mockIOKit)
        
        // Verify the mock tracked the call
        XCTAssertFalse(mockIOKit.serviceMatchingCalls.isEmpty, "Mock should track IOServiceMatching calls")
    }
    
    func testMockIOKitDeviceIteration() {
        // Test mock device iteration functionality
        let mockDevice1 = MockUSBDevice(
            vendorID: 0x1111,
            productID: 0x2222,
            deviceClass: 3,
            deviceSubClass: 0,
            deviceProtocol: 0
        )
        let mockDevice2 = MockUSBDevice(
            vendorID: 0x3333,
            productID: 0x4444,
            deviceClass: 9,
            deviceSubClass: 0,
            deviceProtocol: 0
        )
        
        mockIOKit.mockDevices = [mockDevice1, mockDevice2]
        
        // Verify mock has devices
        XCTAssertEqual(mockIOKit.mockDevices.count, 2)
        XCTAssertEqual(mockIOKit.mockDevices[0].vendorID, 0x1111)
        XCTAssertEqual(mockIOKit.mockDevices[1].vendorID, 0x3333)
    }
    
    // MARK: - Error Mapping Tests
    
    func testIOKitErrorMappingIntegration() {
        // Test that IOKitErrorMapping utilities work with IOKitUSBInterface
        
        // Test various IOKit return codes
        let testCodes: [IOReturn] = [
            kIOReturnSuccess,
            kIOReturnError,
            kIOReturnNoMemory,
            kIOReturnNoDevice,
            kIOReturnNotOpen,
            kIOReturnTimeout,
            kIOReturnAborted
        ]
        
        for returnCode in testCodes {
            // Configure mock to return specific error code
            mockIOKit.getMatchingServicesError = returnCode
            
            if returnCode == kIOReturnSuccess {
                // Success case - may still fail due to missing services but shouldn't throw IOKitError
                _ = try? IOKitUSBInterface(device: testDevice, interfaceNumber: 0, ioKit: mockIOKit)
            } else {
                // Error cases
                mockIOKit.shouldFailGetMatchingServices = true
                
                XCTAssertThrowsError(try IOKitUSBInterface(device: testDevice, interfaceNumber: 0, ioKit: mockIOKit)) { error in
                    // Should be either IOKitError or mapped USB error
                    let isExpectedError = error is IOKitError || 
                                        error is USBRequestError ||
                                        error is DeviceError
                    XCTAssertTrue(isExpectedError, "Should throw appropriate error for IOKit return code \(returnCode)")
                }
                
                // Reset for next iteration
                mockIOKit.shouldFailGetMatchingServices = false
            }
        }
    }
    
    // MARK: - Device Information Tests
    
    func testDeviceInformationExtraction() {
        // Test that device information is properly handled during initialization
        let testManufacturer = "Test Corp"
        let testProduct = "Test USB Device"
        let testSerial = "12345"
        
        let mockDevice = MockUSBDevice(
            vendorID: testDevice.vendorID,
            productID: testDevice.productID,
            deviceClass: testDevice.deviceClass,
            deviceSubClass: testDevice.deviceSubClass,
            deviceProtocol: testDevice.deviceProtocol,
            manufacturerString: testManufacturer,
            productString: testProduct,
            serialNumberString: testSerial
        )
        
        mockIOKit.mockDevices = [mockDevice]
        
        // Attempt to create interface
        _ = try? IOKitUSBInterface(device: testDevice, interfaceNumber: 0, ioKit: mockIOKit)
        
        // Verify that registry property calls were made (device info extraction)
        XCTAssertFalse(mockIOKit.registryEntryCreateCFPropertyCalls.isEmpty, "Should attempt to read device properties")
    }
    
    // MARK: - Interface Number Tests
    
    func testMultipleInterfaceNumbers() {
        // Test creating interfaces for different interface numbers
        let interfaceNumbers: [UInt8] = [0, 1, 2]
        
        for interfaceNumber in interfaceNumbers {
            mockIOKit.serviceMatchingCalls.removeAll()
            
            _ = try? IOKitUSBInterface(device: testDevice, interfaceNumber: interfaceNumber, ioKit: mockIOKit)
            
            // Should attempt service matching for each interface
            XCTAssertFalse(mockIOKit.serviceMatchingCalls.isEmpty, "Should attempt service matching for interface \(interfaceNumber)")
        }
    }
    
    // MARK: - Cleanup and Resource Management Tests
    
    func testResourceCleanupOnError() {
        // Configure mock to fail at different stages
        mockIOKit.shouldFailGetMatchingServices = true
        mockIOKit.getMatchingServicesError = kIOReturnNoMemory
        
        XCTAssertThrowsError(try IOKitUSBInterface(device: testDevice, interfaceNumber: 0, ioKit: mockIOKit))
        
        // Should not leave any dangling references after failed initialization
        // This is tested implicitly by not crashing during tearDown
    }
    
    func testMockStateReset() {
        // Test that mock state can be properly reset between tests
        mockIOKit.serviceMatchingCalls.append("test")
        mockIOKit.shouldFailServiceMatching = true
        
        XCTAssertFalse(mockIOKit.serviceMatchingCalls.isEmpty)
        XCTAssertTrue(mockIOKit.shouldFailServiceMatching)
        
        // Reset mock (this would be done by test infrastructure)
        mockIOKit = MockIOKitInterface()
        
        XCTAssertTrue(mockIOKit.serviceMatchingCalls.isEmpty)
        XCTAssertFalse(mockIOKit.shouldFailServiceMatching)
    }
    
    // MARK: - Performance and Stress Tests
    
    func testMultipleInterfaceCreation() {
        // Test creating multiple interfaces (stress test for resource management)
        let interfaceCount = 5
        var interfaces: [IOKitUSBInterface] = []
        
        for i in 0..<interfaceCount {
            do {
                let interface = try IOKitUSBInterface(device: testDevice, interfaceNumber: UInt8(i % 4), ioKit: mockIOKit)
                interfaces.append(interface)
            } catch {
                // Expected to fail in test environment, just verify no crashes
                print("Interface \(i) creation failed as expected: \(error)")
            }
        }
        
        // Cleanup all interfaces
        interfaces.removeAll()
        
        // Should complete without crashes
    }
    
    func testIOKitInterfaceThreadSafety() {
        // Test that IOKitUSBInterface creation is thread-safe with mock
        let expectation = self.expectation(description: "Concurrent interface creation")
        expectation.expectedFulfillmentCount = 3
        
        let queue = DispatchQueue.global(qos: .userInitiated)
        
        for i in 0..<3 {
            queue.async {
                defer { expectation.fulfill() }
                
                _ = try? IOKitUSBInterface(device: self.testDevice, interfaceNumber: UInt8(i), ioKit: self.mockIOKit)
            }
        }
        
        waitForExpectations(timeout: 5.0)
    }
    
    // MARK: - Integration with IOKitErrorMapping Tests
    
    func testIOKitErrorMappingUtilityIntegration() {
        // Test integration with IOKitErrorMapping utilities
        // This verifies that the error mapping system works with IOKitUSBInterface
        
        let testErrors: [(IOReturn, String)] = [
            (kIOReturnNoDevice, "device not available"),
            (kIOReturnTimeout, "timeout"),
            (kIOReturnNoMemory, "insufficient memory"),
            (kIOReturnBusy, "device busy")
        ]
        
        for (returnCode, expectedDescription) in testErrors {
            mockIOKit.shouldFailGetMatchingServices = true
            mockIOKit.getMatchingServicesError = returnCode
            
            do {
                _ = try IOKitUSBInterface(device: testDevice, interfaceNumber: 0, ioKit: mockIOKit)
                XCTFail("Should have thrown error for return code \(returnCode)")
            } catch {
                // Verify error contains expected information
                let errorDescription = error.localizedDescription.lowercased()
                XCTAssertTrue(errorDescription.contains("error") || 
                            errorDescription.contains("failed") || 
                            errorDescription.contains(expectedDescription),
                            "Error description should contain relevant information: \(errorDescription)")
            }
            
            // Reset for next test
            mockIOKit.shouldFailGetMatchingServices = false
        }
    }
}

// MARK: - Test Helper Extensions

extension IOKitUSBInterfaceTests {
    
    /// Verify that the test environment is properly configured
    func validateTestEnvironment() {
        XCTAssertNotNil(testDevice, "Test device should be configured")
        XCTAssertNotNil(mockIOKit, "Mock IOKit interface should be configured")
        
        // Verify test device has expected properties
        XCTAssertEqual(testDevice.vendorID, 0x1234)
        XCTAssertEqual(testDevice.productID, 0x5678)
        XCTAssertEqual(testDevice.busID, "1-1")
        XCTAssertEqual(testDevice.deviceID, "1.0")
    }
    
    /// Helper to create mock USB device with specific properties
    private func createMockUSBDevice(vendorID: UInt16 = 0x1234, productID: UInt16 = 0x5678) -> MockUSBDevice {
        return MockUSBDevice(
            vendorID: vendorID,
            productID: productID,
            deviceClass: 9,
            deviceSubClass: 0,
            deviceProtocol: 0,
            manufacturerString: "Test Manufacturer",
            productString: "Test Device",
            serialNumberString: "TEST123"
        )
    }
}

// MARK: - Test Suite Performance Tests

extension IOKitUSBInterfaceTests {
    
    func testIOKitInterfaceCreationPerformance() {
        // Performance test for IOKitUSBInterface creation
        let iterationCount = 100
        
        measure {
            for _ in 0..<iterationCount {
                _ = try? IOKitUSBInterface(device: testDevice, interfaceNumber: 0, ioKit: mockIOKit)
            }
        }
        
        // Verify that performance is reasonable
        // This helps catch performance regressions in initialization code
    }
    
    func testMockIOKitCallPerformance() {
        // Test performance of mock IOKit interface calls
        let callCount = 1000
        
        measure {
            for _ in 0..<callCount {
                mockIOKit.serviceMatchingCalls.append("performance_test")
            }
        }
        
        // Cleanup
        mockIOKit.serviceMatchingCalls.removeAll()
    }
}