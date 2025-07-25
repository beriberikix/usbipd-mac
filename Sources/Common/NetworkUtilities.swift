//
// NetworkUtilities.swift
// usbipd-mac
//
// Network utility functions for USB/IP server operations
//

import Foundation
import Network

/// Network utility functions for USB/IP server operations
public enum NetworkUtilities {
    /// Validates if a given string is a valid IPv4 address
    /// - Parameter address: The IP address string to validate
    /// - Returns: True if the address is a valid IPv4 address
    public static func isValidIPv4Address(_ address: String) -> Bool {
        var sin = sockaddr_in()
        return address.withCString { cstring in
            inet_pton(AF_INET, cstring, &sin.sin_addr) == 1
        }
    }
    
    /// Validates if a given string is a valid IPv6 address
    /// - Parameter address: The IP address string to validate
    /// - Returns: True if the address is a valid IPv6 address
    public static func isValidIPv6Address(_ address: String) -> Bool {
        var sin6 = sockaddr_in6()
        return address.withCString { cstring in
            inet_pton(AF_INET6, cstring, &sin6.sin6_addr) == 1
        }
    }
    
    /// Validates if a given string is a valid IP address (IPv4 or IPv6)
    /// - Parameter address: The IP address string to validate
    /// - Returns: True if the address is a valid IP address
    public static func isValidIPAddress(_ address: String) -> Bool {
        isValidIPv4Address(address) || isValidIPv6Address(address)
    }
    
    /// Validates if a given port number is within the valid range
    /// - Parameter port: The port number to validate
    /// - Returns: True if the port is valid (1-65535)
    public static func isValidPort(_ port: Int) -> Bool {
        port > 0 && port <= 65535
    }
    
    /// Checks if a port number is in the well-known port range
    /// - Parameter port: The port number to check
    /// - Returns: True if the port is in the well-known range (1-1023)
    public static func isWellKnownPort(_ port: Int) -> Bool {
        port >= 1 && port <= 1023
    }
    
    /// Creates a standardized network endpoint from host and port
    /// - Parameters:
    ///   - host: The hostname or IP address
    ///   - port: The port number
    /// - Returns: A Network.NWEndpoint if the parameters are valid, nil otherwise
    public static func createEndpoint(host: String, port: Int) -> NWEndpoint? {
        guard isValidPort(port) else {
            logWarning("Invalid port number: \(port)")
            return nil
        }
        
        // Validate IP address format if it looks like an IP
        if isValidIPAddress(host) {
            return NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: UInt16(port))
            )
        }
        
        // For hostnames, let Network framework handle validation
        return NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )
    }
    
    /// Formats a network endpoint as a human-readable string
    /// - Parameter endpoint: The network endpoint to format
    /// - Returns: A formatted string representation of the endpoint
    public static func formatEndpoint(_ endpoint: NWEndpoint) -> String {
        switch endpoint {
        case let .hostPort(host, port):
            "\(host):\(port)"
        case let .service(name, type, domain, _):
            "\(name).\(type).\(domain)"
        case let .unix(path):
            "unix:\(path)"
        case let .url(url):
            url.absoluteString
        case .opaque:
            "opaque endpoint"
        @unknown default:
            "unknown endpoint type"
        }
    }
    
    /// Extracts the port number from a network endpoint
    /// - Parameter endpoint: The network endpoint
    /// - Returns: The port number if available, nil otherwise
    public static func extractPort(from endpoint: NWEndpoint) -> Int? {
        switch endpoint {
        case .hostPort(_, let port):
            return Int(port.rawValue)
        default:
            return nil
        }
    }
    
    /// Extracts the host from a network endpoint
    /// - Parameter endpoint: The network endpoint
    /// - Returns: The host string if available, nil otherwise
    public static func extractHost(from endpoint: NWEndpoint) -> String? {
        switch endpoint {
        case .hostPort(let host, _):
            return String(describing: host)
        default:
            return nil
        }
    }
    
    /// Validates if a given port string can be converted to a valid port number
    /// - Parameter portString: The port string to validate
    /// - Returns: The port number if valid, nil otherwise
    public static func parsePort(_ portString: String) -> Int? {
        guard let port = Int(portString), isValidPort(port) else {
            return nil
        }
        return port
    }
}

/// Extension to provide convenient network validation for common USB/IP operations
public extension String {
    /// Checks if the string represents a valid IP address
    var isValidIPAddress: Bool {
        NetworkUtilities.isValidIPAddress(self)
    }
    
    /// Checks if the string represents a valid IPv4 address
    var isValidIPv4Address: Bool {
        NetworkUtilities.isValidIPv4Address(self)
    }
    
    /// Checks if the string represents a valid IPv6 address
    var isValidIPv6Address: Bool {
        NetworkUtilities.isValidIPv6Address(self)
    }
}

/// Extension to provide convenient port validation
public extension Int {
    /// Checks if the integer represents a valid port number
    var isValidPort: Bool {
        NetworkUtilities.isValidPort(self)
    }
    
    /// Checks if the integer represents a well-known port number (1-1023)
    var isWellKnownPort: Bool {
        NetworkUtilities.isWellKnownPort(self)
    }
}