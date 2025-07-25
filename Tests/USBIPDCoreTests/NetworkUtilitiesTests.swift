//
// NetworkUtilitiesTests.swift
// usbipd-mac
//
// Tests for NetworkUtilities functionality
//

import XCTest
import Network
@testable import Common

final class NetworkUtilitiesTests: XCTestCase {
    
    // MARK: - IPv4 Address Validation Tests
    
    func testValidIPv4Addresses() {
        let validAddresses = [
            "127.0.0.1",
            "192.168.1.1",
            "10.0.0.1",
            "172.16.0.1",
            "255.255.255.255",
            "0.0.0.0"
        ]
        
        for address in validAddresses {
            XCTAssertTrue(
                NetworkUtilities.isValidIPv4Address(address),
                "Expected \(address) to be a valid IPv4 address"
            )
        }
    }
    
    func testInvalidIPv4Addresses() {
        let invalidAddresses = [
            "256.1.1.1",
            "192.168.1",
            "192.168.1.1.1",
            "192.168.-1.1",
            "not.an.ip.address",
            "",
            "::1"
        ]
        
        for address in invalidAddresses {
            XCTAssertFalse(
                NetworkUtilities.isValidIPv4Address(address),
                "Expected \(address) to be an invalid IPv4 address"
            )
        }
    }
    
    // MARK: - IPv6 Address Validation Tests
    
    func testValidIPv6Addresses() {
        let validAddresses = [
            "::1",
            "2001:db8::1",
            "fe80::1",
            "::ffff:192.168.1.1",
            "2001:0db8:85a3:0000:0000:8a2e:0370:7334"
        ]
        
        for address in validAddresses {
            XCTAssertTrue(
                NetworkUtilities.isValidIPv6Address(address),
                "Expected \(address) to be a valid IPv6 address"
            )
        }
    }
    
    func testInvalidIPv6Addresses() {
        let invalidAddresses = [
            "192.168.1.1",
            "not.an.ip.address",
            "",
            "gggg::1",
            "2001:db8::1::2"
        ]
        
        for address in invalidAddresses {
            XCTAssertFalse(
                NetworkUtilities.isValidIPv6Address(address),
                "Expected \(address) to be an invalid IPv6 address"
            )
        }
    }
    
    // MARK: - General IP Address Validation Tests
    
    func testValidIPAddresses() {
        let validAddresses = [
            "127.0.0.1",
            "::1",
            "192.168.1.1",
            "2001:db8::1"
        ]
        
        for address in validAddresses {
            XCTAssertTrue(
                NetworkUtilities.isValidIPAddress(address),
                "Expected \(address) to be a valid IP address"
            )
        }
    }
    
    func testInvalidIPAddresses() {
        let invalidAddresses = [
            "not.an.ip.address",
            "",
            "256.1.1.1",
            "gggg::1"
        ]
        
        for address in invalidAddresses {
            XCTAssertFalse(
                NetworkUtilities.isValidIPAddress(address),
                "Expected \(address) to be an invalid IP address"
            )
        }
    }
    
    // MARK: - Port Validation Tests
    
    func testValidPorts() {
        let validPorts = [1, 80, 443, 3240, 65535]
        
        for port in validPorts {
            XCTAssertTrue(
                NetworkUtilities.isValidPort(port),
                "Expected \(port) to be a valid port"
            )
        }
    }
    
    func testInvalidPorts() {
        let invalidPorts = [0, -1, 65536, 100000]
        
        for port in invalidPorts {
            XCTAssertFalse(
                NetworkUtilities.isValidPort(port),
                "Expected \(port) to be an invalid port"
            )
        }
    }
    
    func testWellKnownPorts() {
        let wellKnownPorts = [1, 22, 80, 443, 1023]
        
        for port in wellKnownPorts {
            XCTAssertTrue(
                NetworkUtilities.isWellKnownPort(port),
                "Expected \(port) to be a well-known port"
            )
        }
    }
    
    func testNonWellKnownPorts() {
        let nonWellKnownPorts = [0, 1024, 3240, 8080, 65535, -1]
        
        for port in nonWellKnownPorts {
            XCTAssertFalse(
                NetworkUtilities.isWellKnownPort(port),
                "Expected \(port) to not be a well-known port"
            )
        }
    }
    
    // MARK: - Endpoint Creation Tests
    
    func testCreateValidEndpoint() {
        let endpoint = NetworkUtilities.createEndpoint(host: "127.0.0.1", port: 3240)
        XCTAssertNotNil(endpoint, "Expected endpoint to be created successfully")
        
        if let endpoint = endpoint {
            let formatted = NetworkUtilities.formatEndpoint(endpoint)
            XCTAssertTrue(formatted.contains("127.0.0.1"), "Expected formatted endpoint to contain host")
            XCTAssertTrue(formatted.contains("3240"), "Expected formatted endpoint to contain port")
        }
    }
    
    func testCreateEndpointWithInvalidPort() {
        let endpoint = NetworkUtilities.createEndpoint(host: "127.0.0.1", port: 0)
        XCTAssertNil(endpoint, "Expected endpoint creation to fail with invalid port")
    }
    
    func testCreateEndpointWithHostname() {
        let endpoint = NetworkUtilities.createEndpoint(host: "localhost", port: 3240)
        XCTAssertNotNil(endpoint, "Expected endpoint to be created with hostname")
    }
    
    // MARK: - Endpoint Extraction Tests
    
    func testExtractPortFromEndpoint() {
        guard let endpoint = NetworkUtilities.createEndpoint(host: "127.0.0.1", port: 3240) else {
            XCTFail("Failed to create test endpoint")
            return
        }
        
        let extractedPort = NetworkUtilities.extractPort(from: endpoint)
        XCTAssertEqual(extractedPort, 3240, "Expected extracted port to match original")
    }
    
    func testExtractHostFromEndpoint() {
        guard let endpoint = NetworkUtilities.createEndpoint(host: "127.0.0.1", port: 3240) else {
            XCTFail("Failed to create test endpoint")
            return
        }
        
        let extractedHost = NetworkUtilities.extractHost(from: endpoint)
        XCTAssertNotNil(extractedHost, "Expected to extract host from endpoint")
        XCTAssertTrue(extractedHost?.contains("127.0.0.1") == true, "Expected extracted host to contain IP address")
    }
    
    // MARK: - String Extension Tests
    
    func testStringIPValidationExtensions() {
        XCTAssertTrue("127.0.0.1".isValidIPAddress)
        XCTAssertTrue("127.0.0.1".isValidIPv4Address)
        XCTAssertFalse("127.0.0.1".isValidIPv6Address)
        
        XCTAssertTrue("::1".isValidIPAddress)
        XCTAssertFalse("::1".isValidIPv4Address)
        XCTAssertTrue("::1".isValidIPv6Address)
        
        XCTAssertFalse("invalid".isValidIPAddress)
        XCTAssertFalse("invalid".isValidIPv4Address)
        XCTAssertFalse("invalid".isValidIPv6Address)
    }
    
    // MARK: - Int Extension Tests
    
    func testIntPortValidationExtension() {
        XCTAssertTrue(3240.isValidPort)
        XCTAssertTrue(1.isValidPort)
        XCTAssertTrue(65535.isValidPort)
        
        XCTAssertFalse(0.isValidPort)
        XCTAssertFalse((-1).isValidPort)
        XCTAssertFalse(65536.isValidPort)
    }
    
    func testIntWellKnownPortExtension() {
        XCTAssertTrue(80.isWellKnownPort)
        XCTAssertTrue(443.isWellKnownPort)
        XCTAssertTrue(22.isWellKnownPort)
        XCTAssertTrue(1.isWellKnownPort)
        XCTAssertTrue(1023.isWellKnownPort)
        
        XCTAssertFalse(1024.isWellKnownPort)
        XCTAssertFalse(3240.isWellKnownPort)
        XCTAssertFalse(8080.isWellKnownPort)
        XCTAssertFalse(0.isWellKnownPort)
        XCTAssertFalse((-1).isWellKnownPort)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyStringValidation() {
        XCTAssertFalse("".isValidIPAddress)
        XCTAssertFalse("".isValidIPv4Address)
        XCTAssertFalse("".isValidIPv6Address)
    }
    
    func testWhitespaceStringValidation() {
        XCTAssertFalse(" ".isValidIPAddress)
        XCTAssertFalse("  127.0.0.1  ".isValidIPv4Address) // Leading/trailing whitespace should fail
    }
    
    // MARK: - Port Parsing Tests
    
    func testParseValidPortStrings() {
        let validPortStrings = [
            ("1", 1),
            ("80", 80),
            ("443", 443),
            ("3240", 3240),
            ("65535", 65535)
        ]
        
        for (portString, expectedPort) in validPortStrings {
            let parsedPort = NetworkUtilities.parsePort(portString)
            XCTAssertEqual(
                parsedPort,
                expectedPort,
                "Expected '\(portString)' to parse to \(expectedPort)"
            )
        }
    }
    
    func testParseInvalidPortStrings() {
        let invalidPortStrings = [
            "0",        // Invalid port number
            "-1",       // Negative number
            "65536",    // Too large
            "abc",      // Non-numeric
            "",         // Empty string
            " ",        // Whitespace
            "80.5",     // Decimal
            "80a",      // Mixed alphanumeric
            "999999"    // Way too large
        ]
        
        for portString in invalidPortStrings {
            let parsedPort = NetworkUtilities.parsePort(portString)
            XCTAssertNil(
                parsedPort,
                "Expected '\(portString)' to fail parsing"
            )
        }
    }
}