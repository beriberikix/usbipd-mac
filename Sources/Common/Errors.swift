// Errors.swift
// Common error definitions for the project

import Foundation


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

/// Device discovery specific errors
public enum DeviceDiscoveryError: Error {
    case ioKitError(Int32, String)
    case deviceNotFound(String)
    case accessDenied(String)
    case initializationFailed(String)
    case failedToCreateMatchingDictionary
    case failedToGetMatchingServices(Int32)
    case missingProperty(String)
    case invalidPropertyType(String)
    case failedToCreateNotificationPort
    case failedToAddNotification(Int32)
}

extension DeviceDiscoveryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .ioKitError(code, message):
            return "IOKit error (code: \(code)): \(message)"
        case .deviceNotFound(let identifier):
            return "Device not found: \(identifier)"
        case .accessDenied(let message):
            return "Access denied: \(message)"
        case .initializationFailed(let message):
            return "Initialization failed: \(message)"
        case .failedToCreateMatchingDictionary:
            return "Failed to create IOKit matching dictionary"
        case .failedToGetMatchingServices(let code):
            return "Failed to get matching services (code: \(code))"
        case .missingProperty(let property):
            return "Missing required property: \(property)"
        case .invalidPropertyType(let property):
            return "Invalid property type for: \(property)"
        case .failedToCreateNotificationPort:
            return "Failed to create IOKit notification port"
        case .failedToAddNotification(let code):
            return "Failed to add notification (code: \(code))"
        }
    }
}

/// Server-related errors
public enum ServerError: Error {
    case alreadyRunning
    case notRunning
    case initializationFailed(String)
    case configurationError(String)
    case systemExtensionFailed(String)
}