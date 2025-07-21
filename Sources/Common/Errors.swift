// Errors.swift
// Common error definitions for the project

import Foundation

/// Protocol-related errors
public enum USBIPProtocolError: Error {
    case invalidHeader
    case invalidMessageFormat
    case unsupportedVersion(UInt16)
    case unsupportedCommand(UInt16)
    case invalidDataLength
}

/// Network-related errors
public enum NetworkError: Error {
    case connectionFailed(String)
    case connectionClosed
    case sendFailed(String)
    case receiveFailed(String)
    case bindFailed(String)
}

/// Device-related errors
public enum DeviceError: Error {
    case deviceNotFound(String)
    case accessDenied(String)
    case ioKitError(Int32, String)
}

/// Server-related errors
public enum ServerError: Error {
    case alreadyRunning
    case notRunning
    case initializationFailed(String)
}