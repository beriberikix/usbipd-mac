// OutputFormatterTests.swift
// Tests for output formatters

import XCTest
import Foundation
@testable import USBIPDCLI
@testable import USBIPDCore
@testable import Common

class OutputFormatterTests: XCTestCase {
    
    var testDevices: [USBDevice] = []
    
    override func setUp() {
        super.setUp()
        
        // Set up test devices
        testDevices = [
            USBDevice(
                busID: "1",
                deviceID: "2",
                vendorID: 0x1234,
                productID: 0x5678,
                deviceClass: 0x09,
                deviceSubClass: 0x00,
                deviceProtocol: 0x00,
                speed: .high,
                manufacturerString: "Mock Manufacturer",
                productString: "Mock Device",
                serialNumberString: "12345"
            ),
            USBDevice(
                busID: "1",
                deviceID: "3",
                vendorID: 0xABCD,
                productID: 0xEF01,
                deviceClass: 0x03,
                deviceSubClass: 0x01,
                deviceProtocol: 0x02,
                speed: .superSpeed,
                manufacturerString: "Another Manufacturer",
                productString: "Another Device",
                serialNumberString: "67890"
            )
        ]
    }
    
    override func tearDown() {
        testDevices = []
        super.tearDown()
    }
    
    // MARK: - DefaultOutputFormatter Tests
    
    func testDefaultOutputFormatterDeviceList() {
        let formatter = DefaultOutputFormatter()
        let output = formatter.formatDeviceList(testDevices)
        
        // Check that output contains expected strings
        XCTAssertTrue(output.contains("1-2"), "Output should contain device busid")
        XCTAssertTrue(output.contains("1234:5678"), "Output should contain device vendor/product IDs")
        XCTAssertTrue(output.contains("Mock Device"), "Output should contain device name")
        XCTAssertTrue(output.contains("1-3"), "Output should contain second device busid")
        XCTAssertTrue(output.contains("abcd:ef01"), "Output should contain second device vendor/product IDs")
        XCTAssertTrue(output.contains("Another Device"), "Output should contain second device name")
    }
    
    func testDefaultOutputFormatterSingleDevice() {
        let formatter = DefaultOutputFormatter()
        let output = formatter.formatDevice(testDevices[0], detailed: false)
        
        XCTAssertTrue(output.contains("1-2"), "Output should contain device busid")
        XCTAssertTrue(output.contains("1234:5678"), "Output should contain device vendor/product IDs")
        XCTAssertTrue(output.contains("Mock Device"), "Output should contain device name")
    }
    
    func testDefaultOutputFormatterError() {
        let formatter = DefaultOutputFormatter()
        let error = NSError(domain: "test", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let output = formatter.formatError(error)
        
        XCTAssertTrue(output.contains("Error:"), "Output should start with 'Error:'")
        XCTAssertTrue(output.contains("Test error"), "Output should contain error description")
    }
    
    func testDefaultOutputFormatterSuccess() {
        let formatter = DefaultOutputFormatter()
        let output = formatter.formatSuccess("Operation successful")
        
        XCTAssertEqual(output, "Operation successful", "Output should match input message")
    }
    
    // MARK: - LinuxCompatibleOutputFormatter Tests
    
    func testLinuxCompatibleOutputFormatterDeviceList() {
        let formatter = LinuxCompatibleOutputFormatter()
        let output = formatter.formatDeviceList(testDevices)
        
        // Check that output contains expected strings
        XCTAssertTrue(output.contains("Local USB Device(s)"), "Output should contain header")
        XCTAssertTrue(output.contains("Busid  Dev-Node"), "Output should contain column headers")
        XCTAssertTrue(output.contains("1-2"), "Output should contain device busid")
        // Use a more flexible assertion for the device node path
        let devNodePattern = "/dev/bus/usb/\\d+/\\d+"
        let devNodeRegex = try! NSRegularExpression(pattern: devNodePattern)
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        let matches = devNodeRegex.matches(in: output, range: range)
        XCTAssertTrue(matches.count > 0, "Output should contain device node matching pattern \(devNodePattern)")
        
        XCTAssertTrue(output.contains("1234:5678"), "Output should contain device vendor/product IDs")
        XCTAssertTrue(output.contains("Mock Device"), "Output should contain device name")
    }
    
    func testLinuxCompatibleOutputFormatterEmptyDeviceList() {
        let formatter = LinuxCompatibleOutputFormatter()
        let output = formatter.formatDeviceList([])
        
        XCTAssertTrue(output.contains("No USB devices found"), "Output should indicate no devices")
    }
    
    func testLinuxCompatibleOutputFormatterDetailedDevice() {
        let formatter = LinuxCompatibleOutputFormatter()
        let output = formatter.formatDevice(testDevices[0], detailed: true)
        
        XCTAssertTrue(output.contains("Device: 1-2"), "Output should contain device identifier")
        XCTAssertTrue(output.contains("Vendor ID: 1234"), "Output should contain vendor ID")
        XCTAssertTrue(output.contains("Product ID: 5678"), "Output should contain product ID")
        XCTAssertTrue(output.contains("Manufacturer: Mock Manufacturer"), "Output should contain manufacturer")
        XCTAssertTrue(output.contains("Product: Mock Device"), "Output should contain product name")
        XCTAssertTrue(output.contains("Serial Number: 12345"), "Output should contain serial number")
        XCTAssertTrue(output.contains("Speed: High"), "Output should contain speed")
    }
    
    func testLinuxCompatibleOutputFormatterNonDetailedDevice() {
        let formatter = LinuxCompatibleOutputFormatter()
        let output = formatter.formatDevice(testDevices[0], detailed: false)
        
        XCTAssertTrue(output.contains("1-2"), "Output should contain device busid")
        XCTAssertTrue(output.contains("1234:5678"), "Output should contain device vendor/product IDs")
        XCTAssertTrue(output.contains("Mock Device"), "Output should contain device name")
    }
    
    func testLinuxCompatibleOutputFormatterError() {
        let formatter = LinuxCompatibleOutputFormatter()
        let error = NSError(domain: "test", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let output = formatter.formatError(error)
        
        XCTAssertTrue(output.contains("Error:"), "Output should start with 'Error:'")
        XCTAssertTrue(output.contains("Test error"), "Output should contain error description")
    }
    
    func testLinuxCompatibleOutputFormatterSuccess() {
        let formatter = LinuxCompatibleOutputFormatter()
        let output = formatter.formatSuccess("Operation successful")
        
        XCTAssertEqual(output, "Operation successful", "Output should match input message")
    }
}