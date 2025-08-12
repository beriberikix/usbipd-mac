// MockIOKitInterface.swift
// Comprehensive IOKit mock interface for development environment testing
// Consolidates and enhances mocks from USBIPDCoreTests and SystemExtensionTests
// Enables reliable, fast testing without hardware dependencies

import Foundation
import IOKit
import IOKit.usb
import Common
@testable import USBIPDCore

// MARK: - Development Environment Mock IOKit Interface

/// Comprehensive IOKit mock interface optimized for development environment testing
/// Combines functionality from MockIOKitInterface and MockSystemExtensionIOKit
/// with enhanced debugging and reliability features for rapid development cycles
public class DevelopmentMockIOKitInterface: IOKitInterface {
    
    // MARK: - Mock State Management
    
    /// Mock devices that will be returned by discovery operations
    public var mockDevices: [MockUSBDevice] = []
    
    /// Controls basic operation failures
    public var shouldFailServiceMatching = false
    public var shouldFailGetMatchingServices = false
    public var getMatchingServicesError: kern_return_t = KERN_FAILURE
    
    /// Controls notification system failures
    public var shouldFailNotificationPortCreate = false
    public var shouldFailAddNotification = false
    public var addNotificationError: kern_return_t = KERN_FAILURE
    public var shouldFailNotificationSetup = false
    public var notificationSetupError: Error?
    
    /// Controls device claiming operations (System Extension support)
    public var claimableDevices: Set<io_service_t> = []
    public var alreadyClaimedDevices: Set<io_service_t> = []
    public var deviceClaimErrors: [io_service_t: kern_return_t] = [:]
    public var deviceReleaseErrors: [io_service_t: kern_return_t] = [:]
    
    // MARK: - Operation Tracking
    
    /// Comprehensive tracking of all IOKit operations for test verification
    public var serviceMatchingCalls: [String] = []
    public var serviceGetMatchingServicesCalls: [(mach_port_t, CFDictionary)] = []
    public var iteratorNextCalls: [io_iterator_t] = []
    public var objectReleaseCalls: [io_object_t] = []
    public var registryEntryCreateCFPropertyCalls: [(io_registry_entry_t, String)] = []
    public var notificationPortCreateCalls: [mach_port_t] = []
    public var serviceAddMatchingNotificationCalls: [(IONotificationPortRef, String)] = []
    public var notificationPortGetRunLoopSourceCalls: [IONotificationPortRef] = []
    public var notificationPortSetDispatchQueueCalls: [(IONotificationPortRef, DispatchQueue?)] = []
    public var notificationPortDestroyCalls: [IONotificationPortRef] = []
    
    /// System Extension operation tracking
    public var deviceClaimCalls: [io_service_t] = []
    public var deviceReleaseCalls: [io_service_t] = []
    public var exclusiveAccessChecks: [io_service_t] = []
    public var exclusiveAccessResults: [io_service_t: Bool] = [:]
    public var driverUnbindCalls: [io_service_t] = []
    public var driverUnbindResults: [io_service_t: kern_return_t] = [:]
    
    // MARK: - Iterator Management
    
    private var currentIteratorIndex = 0
    private var mockIteratorValue: io_iterator_t = 1000
    private var mockServiceValue: io_service_t = 2000
    
    // MARK: - Notification System State
    
    private var deviceAddedCallback: IOServiceMatchingCallback?
    private var deviceRemovedCallback: IOServiceMatchingCallback?
    private var callbackRefCon: UnsafeMutableRawPointer?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    
    /// Enhanced notification device management
    private var notificationDevices: [MockUSBDevice] = []
    private var addedNotificationDevices: [MockUSBDevice] = []
    private var removedNotificationDevices: [MockUSBDevice] = []
    private var addedNotificationIndex = 0
    private var removedNotificationIndex = 0
    
    // MARK: - Development Environment Features
    
    /// Enable detailed debug logging for development troubleshooting
    public var debugLoggingEnabled = true
    
    /// Simulate various error conditions for comprehensive testing
    private var simulatedDiscoveryError: Error?
    
    /// Performance tracking for development optimization
    public private(set) var operationTimings: [String: TimeInterval] = [:]
    
    /// Current claim method being tested (for System Extension testing)
    public var currentClaimMethod: DeviceClaimMethod = .exclusiveAccess
    
    public init() {
        setupDefaultMockDevices()
    }
    
    // MARK: - Reset and Configuration
    
    /// Comprehensive reset for clean test state
    public func reset() {
        mockDevices.removeAll()
        shouldFailServiceMatching = false
        shouldFailGetMatchingServices = false
        getMatchingServicesError = KERN_FAILURE
        shouldFailNotificationPortCreate = false
        shouldFailAddNotification = false
        addNotificationError = KERN_FAILURE
        shouldFailNotificationSetup = false
        notificationSetupError = nil
        
        // System Extension state
        claimableDevices.removeAll()
        alreadyClaimedDevices.removeAll()
        deviceClaimErrors.removeAll()
        deviceReleaseErrors.removeAll()
        
        // Clear all tracking arrays
        serviceMatchingCalls.removeAll()
        serviceGetMatchingServicesCalls.removeAll()
        iteratorNextCalls.removeAll()
        objectReleaseCalls.removeAll()
        registryEntryCreateCFPropertyCalls.removeAll()
        notificationPortCreateCalls.removeAll()
        serviceAddMatchingNotificationCalls.removeAll()
        notificationPortGetRunLoopSourceCalls.removeAll()
        notificationPortSetDispatchQueueCalls.removeAll()
        notificationPortDestroyCalls.removeAll()
        
        deviceClaimCalls.removeAll()
        deviceReleaseCalls.removeAll()
        exclusiveAccessChecks.removeAll()
        exclusiveAccessResults.removeAll()
        driverUnbindCalls.removeAll()
        driverUnbindResults.removeAll()
        
        // Reset notification state
        currentIteratorIndex = 0
        deviceAddedCallback = nil
        deviceRemovedCallback = nil
        callbackRefCon = nil
        addedIterator = 0
        removedIterator = 0
        notificationDevices.removeAll()
        addedNotificationDevices.removeAll()
        removedNotificationDevices.removeAll()
        addedNotificationIndex = 0
        removedNotificationIndex = 0
        
        // Reset development features
        simulatedDiscoveryError = nil
        operationTimings.removeAll()
        currentClaimMethod = .exclusiveAccess
        
        setupDefaultMockDevices()
    }
    
    // MARK: - IOKitInterface Implementation
    
    public func serviceMatching(_ name: String) -> CFMutableDictionary? {
        let startTime = CFAbsoluteTimeGetCurrent()
        serviceMatchingCalls.append(name)
        
        if debugLoggingEnabled {
            print("MOCK: serviceMatching(\(name))")
        }
        
        if shouldFailServiceMatching {
            if debugLoggingEnabled {
                print("MOCK: serviceMatching failed (configured to fail)")
            }
            return nil
        }
        
        // Create mock dictionary
        var keyCallbacks = kCFTypeDictionaryKeyCallBacks
        var valueCallbacks = kCFTypeDictionaryValueCallBacks
        let dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &keyCallbacks, &valueCallbacks)
        CFDictionarySetValue(dict, Unmanaged.passRetained("IOProviderClass" as CFString).toOpaque(), Unmanaged.passRetained(name as CFString).toOpaque())
        
        operationTimings["serviceMatching"] = CFAbsoluteTimeGetCurrent() - startTime
        return dict
    }
    
    public func serviceGetMatchingServices(_ mainPort: mach_port_t, _ matching: CFDictionary, _ existing: UnsafeMutablePointer<io_iterator_t>) -> kern_return_t {
        let startTime = CFAbsoluteTimeGetCurrent()
        serviceGetMatchingServicesCalls.append((mainPort, matching))
        
        if debugLoggingEnabled {
            print("MOCK: serviceGetMatchingServices(port: \(mainPort), devices: \(mockDevices.count))")
        }
        
        if shouldFailGetMatchingServices {
            if debugLoggingEnabled {
                print("MOCK: serviceGetMatchingServices failed with error: \(getMatchingServicesError)")
            }
            return getMatchingServicesError
        }
        
        // Set up iterator for mock devices
        currentIteratorIndex = 0
        existing.pointee = mockIteratorValue
        
        operationTimings["serviceGetMatchingServices"] = CFAbsoluteTimeGetCurrent() - startTime
        return KERN_SUCCESS
    }
    
    public func iteratorNext(_ iterator: io_iterator_t) -> io_service_t {
        iteratorNextCalls.append(iterator)
        
        if debugLoggingEnabled {
            print("MOCK: iteratorNext(\(iterator))")
        }
        
        // Handle notification iterators
        if iterator == addedIterator {
            if debugLoggingEnabled {
                print("MOCK: iteratorNext for addedIterator, index: \(addedNotificationIndex), devices: \(addedNotificationDevices.count)")
            }
            if addedNotificationIndex < addedNotificationDevices.count {
                let service = io_service_t(mockServiceValue + 1000 + UInt32(addedNotificationIndex))
                addedNotificationIndex += 1
                return service
            }
            return 0
        }
        
        if iterator == removedIterator {
            if debugLoggingEnabled {
                print("MOCK: iteratorNext for removedIterator, index: \(removedNotificationIndex), devices: \(removedNotificationDevices.count)")
            }
            if removedNotificationIndex < removedNotificationDevices.count {
                let service = io_service_t(mockServiceValue + 2000 + UInt32(removedNotificationIndex))
                removedNotificationIndex += 1
                return service
            }
            return 0
        }
        
        // Handle regular discovery iterator
        if currentIteratorIndex < mockDevices.count {
            let service = io_service_t(mockServiceValue + UInt32(currentIteratorIndex))
            currentIteratorIndex += 1
            if debugLoggingEnabled {
                print("MOCK: iteratorNext returning service \(service) for device \(currentIteratorIndex - 1)")
            }
            return service
        }
        
        if debugLoggingEnabled {
            print("MOCK: iteratorNext end of iteration")
        }
        return 0
    }
    
    public func objectRelease(_ object: io_object_t) -> kern_return_t {
        objectReleaseCalls.append(object)
        
        if debugLoggingEnabled {
            print("MOCK: objectRelease(\(object))")
        }
        
        return KERN_SUCCESS
    }
    
    public func registryEntryCreateCFProperty(_ entry: io_registry_entry_t, _ key: CFString, _ allocator: CFAllocator?, _ options: IOOptionBits) -> Unmanaged<CFTypeRef>? {
        let keyString = key as String
        registryEntryCreateCFPropertyCalls.append((entry, keyString))
        
        if debugLoggingEnabled {
            print("MOCK: registryEntryCreateCFProperty(entry: \(entry), key: \(keyString))")
        }
        
        // Handle notification services
        if entry >= mockServiceValue + 1000 && entry < mockServiceValue + 2000 {
            // Added notification device
            let deviceIndex = Int(entry - mockServiceValue - 1000)
            if deviceIndex >= 0 && deviceIndex < addedNotificationDevices.count {
                let mockDevice = addedNotificationDevices[deviceIndex]
                return mockDevice.getProperty(key: keyString)
            }
        } else if entry >= mockServiceValue + 2000 && entry < mockServiceValue + 3000 {
            // Removed notification device
            let deviceIndex = Int(entry - mockServiceValue - 2000)
            if deviceIndex >= 0 && deviceIndex < removedNotificationDevices.count {
                let mockDevice = removedNotificationDevices[deviceIndex]
                return mockDevice.getProperty(key: keyString)
            }
        } else {
            // Regular discovery device
            let serviceIndex = Int(entry - mockServiceValue)
            if serviceIndex >= 0 && serviceIndex < mockDevices.count {
                let mockDevice = mockDevices[serviceIndex]
                return mockDevice.getProperty(key: keyString)
            }
        }
        
        if debugLoggingEnabled {
            print("MOCK: registryEntryCreateCFProperty returning nil for unknown service")
        }
        return nil
    }
    
    public func notificationPortCreate(_ mainPort: mach_port_t) -> IONotificationPortRef? {
        notificationPortCreateCalls.append(mainPort)
        
        if debugLoggingEnabled {
            print("MOCK: notificationPortCreate(\(mainPort))")
        }
        
        if shouldFailNotificationPortCreate {
            if debugLoggingEnabled {
                print("MOCK: notificationPortCreate failed (configured to fail)")
            }
            return nil
        }
        
        // Return mock notification port
        return OpaquePointer(bitPattern: 0x12345678)
    }
    
    public func serviceAddMatchingNotification(_ notifyPort: IONotificationPortRef, _ notificationType: String, _ matching: CFDictionary, _ callback: IOServiceMatchingCallback?, _ refCon: UnsafeMutableRawPointer?, _ notification: UnsafeMutablePointer<io_iterator_t>) -> kern_return_t {
        serviceAddMatchingNotificationCalls.append((notifyPort, notificationType))
        
        if debugLoggingEnabled {
            print("MOCK: serviceAddMatchingNotification(type: \(notificationType))")
        }
        
        if shouldFailAddNotification {
            if debugLoggingEnabled {
                print("MOCK: serviceAddMatchingNotification failed with error: \(addNotificationError)")
            }
            return addNotificationError
        }
        
        // Store callback and refcon for simulation
        if notificationType == kIOFirstMatchNotification {
            deviceAddedCallback = callback
            addedIterator = io_iterator_t(mockIteratorValue + 100)
            notification.pointee = addedIterator
        } else if notificationType == kIOTerminatedNotification {
            deviceRemovedCallback = callback
            removedIterator = io_iterator_t(mockIteratorValue + 200)
            notification.pointee = removedIterator
        }
        
        callbackRefCon = refCon
        return KERN_SUCCESS
    }
    
    public func notificationPortGetRunLoopSource(_ notify: IONotificationPortRef) -> CFRunLoopSource? {
        notificationPortGetRunLoopSourceCalls.append(notify)
        
        if debugLoggingEnabled {
            print("MOCK: notificationPortGetRunLoopSource")
        }
        
        // Return mock run loop source
        return CFRunLoopSourceCreate(kCFAllocatorDefault, 0, nil)
    }
    
    public func notificationPortSetDispatchQueue(_ notify: IONotificationPortRef, _ queue: DispatchQueue?) {
        notificationPortSetDispatchQueueCalls.append((notify, queue))
        
        if debugLoggingEnabled {
            print("MOCK: notificationPortSetDispatchQueue")
        }
    }
    
    public func notificationPortDestroy(_ notify: IONotificationPortRef) {
        notificationPortDestroyCalls.append(notify)
        
        if debugLoggingEnabled {
            print("MOCK: notificationPortDestroy")
        }
    }
    
    // MARK: - System Extension Support
    
    /// Configure a device to be successfully claimable
    public func makeDeviceClaimable(service: io_service_t) {
        claimableDevices.insert(service)
        alreadyClaimedDevices.remove(service)
        deviceClaimErrors.removeValue(forKey: service)
        
        if debugLoggingEnabled {
            print("MOCK: Device \(service) configured as claimable")
        }
    }
    
    /// Configure a device to be already claimed
    public func makeDeviceAlreadyClaimed(service: io_service_t) {
        alreadyClaimedDevices.insert(service)
        claimableDevices.remove(service)
        
        if debugLoggingEnabled {
            print("MOCK: Device \(service) configured as already claimed")
        }
    }
    
    /// Configure a device to fail claiming with specific error
    public func makeDeviceClaimFail(service: io_service_t, error: kern_return_t) {
        deviceClaimErrors[service] = error
        claimableDevices.remove(service)
        
        if debugLoggingEnabled {
            print("MOCK: Device \(service) configured to fail claiming with error: \(error)")
        }
    }
    
    /// Simulate device claiming operation
    public func simulateDeviceClaim(service: io_service_t) -> kern_return_t {
        deviceClaimCalls.append(service)
        
        if debugLoggingEnabled {
            print("MOCK: simulateDeviceClaim(\(service))")
        }
        
        // Check if device should fail claiming
        if let error = deviceClaimErrors[service] {
            if debugLoggingEnabled {
                print("MOCK: Device claim failed with configured error: \(error)")
            }
            return error
        }
        
        // Check if device is already claimed
        if alreadyClaimedDevices.contains(service) {
            if debugLoggingEnabled {
                print("MOCK: Device already claimed")
            }
            return KERN_RESOURCE_SHORTAGE
        }
        
        // Check if device is claimable
        if claimableDevices.contains(service) {
            alreadyClaimedDevices.insert(service)
            claimableDevices.remove(service)
            if debugLoggingEnabled {
                print("MOCK: Device claimed successfully")
            }
            return KERN_SUCCESS
        }
        
        if debugLoggingEnabled {
            print("MOCK: Device not found or not claimable")
        }
        return KERN_FAILURE
    }
    
    /// Simulate device releasing operation
    public func simulateDeviceRelease(service: io_service_t) -> kern_return_t {
        deviceReleaseCalls.append(service)
        
        if debugLoggingEnabled {
            print("MOCK: simulateDeviceRelease(\(service))")
        }
        
        // Check if device should fail releasing
        if let error = deviceReleaseErrors[service] {
            if debugLoggingEnabled {
                print("MOCK: Device release failed with configured error: \(error)")
            }
            return error
        }
        
        // Check if device is actually claimed
        if alreadyClaimedDevices.contains(service) {
            alreadyClaimedDevices.remove(service)
            claimableDevices.insert(service)
            if debugLoggingEnabled {
                print("MOCK: Device released successfully")
            }
            return KERN_SUCCESS
        }
        
        if debugLoggingEnabled {
            print("MOCK: Device not claimed, cannot release")
        }
        return KERN_INVALID_ARGUMENT
    }
    
    /// Simulate exclusive access check
    public func simulateExclusiveAccessCheck(service: io_service_t) -> Bool {
        exclusiveAccessChecks.append(service)
        
        if debugLoggingEnabled {
            print("MOCK: simulateExclusiveAccessCheck(\(service))")
        }
        
        // Return configured result or default based on claim status
        if let result = exclusiveAccessResults[service] {
            if debugLoggingEnabled {
                print("MOCK: Exclusive access check returning configured result: \(result)")
            }
            return result
        }
        
        // Default: can get exclusive access if device is claimable
        let result = claimableDevices.contains(service)
        if debugLoggingEnabled {
            print("MOCK: Exclusive access check returning default result: \(result)")
        }
        return result
    }
    
    // MARK: - Notification Simulation
    
    /// Simulate a device connection notification
    public func simulateDeviceConnection(_ device: USBDevice) {
        let mockDevice = createMockDevice(from: device)
        
        notificationDevices.append(mockDevice)
        addedNotificationDevices = [mockDevice]
        addedNotificationIndex = 0
        
        if debugLoggingEnabled {
            print("MOCK: Simulating device connection: \(device.productString ?? "Unknown Device")")
        }
        
        // Trigger callback if set
        if let callback = deviceAddedCallback {
            callback(callbackRefCon, addedIterator)
        }
    }
    
    /// Simulate a device disconnection notification
    public func simulateDeviceDisconnection(_ device: USBDevice) {
        let mockDevice = createMockDevice(from: device)
        
        // Remove from notification devices
        notificationDevices.removeAll { existingDevice in
            existingDevice.vendorID == device.vendorID &&
            existingDevice.productID == device.productID &&
            existingDevice.locationID == mockDevice.locationID
        }
        
        removedNotificationDevices = [mockDevice]
        removedNotificationIndex = 0
        
        if debugLoggingEnabled {
            print("MOCK: Simulating device disconnection: \(device.productString ?? "Unknown Device")")
        }
        
        // Trigger callback if set
        if let callback = deviceRemovedCallback {
            callback(callbackRefCon, removedIterator)
        }
    }
    
    // MARK: - Development Environment Helpers
    
    /// Set up predefined test scenarios for common development patterns
    public func setupDevelopmentScenario(_ scenario: DevelopmentTestScenario) {
        reset()
        
        switch scenario {
        case .happyPath:
            setupHappyPathScenario()
        case .noDevicesFound:
            setupNoDevicesScenario()
        case .notificationFailure:
            setupNotificationFailureScenario()
        case .claimingFailure:
            setupClaimingFailureScenario()
        case .mixedResults:
            setupMixedResultsScenario()
        }
    }
    
    /// Get comprehensive statistics for test verification
    public func getDevelopmentStatistics() -> DevelopmentMockStatistics {
        return DevelopmentMockStatistics(
            totalOperationCalls: serviceMatchingCalls.count + serviceGetMatchingServicesCalls.count + iteratorNextCalls.count,
            deviceDiscoveryCalls: serviceGetMatchingServicesCalls.count,
            notificationCalls: serviceAddMatchingNotificationCalls.count,
            deviceClaimAttempts: deviceClaimCalls.count,
            deviceReleaseAttempts: deviceReleaseCalls.count,
            currentlyMockedDevices: mockDevices.count,
            operationTimings: operationTimings
        )
    }
    
    // MARK: - Private Helper Methods
    
    private func setupDefaultMockDevices() {
        // Add standard test devices for development
        mockDevices = [
            USBDeviceTestFixtures.appleMagicMouse.toMockUSBDevice(),
            USBDeviceTestFixtures.logitechKeyboard.toMockUSBDevice(),
            USBDeviceTestFixtures.sandiskFlashDrive.toMockUSBDevice()
        ]
        
        // Make all devices claimable by default in development environment
        for i in 0..<mockDevices.count {
            let service = io_service_t(mockServiceValue + UInt32(i))
            claimableDevices.insert(service)
        }
    }
    
    private func createMockDevice(from device: USBDevice) -> MockUSBDevice {
        return MockUSBDevice(
            vendorID: device.vendorID,
            productID: device.productID,
            deviceClass: device.deviceClass,
            deviceSubClass: device.deviceSubClass,
            deviceProtocol: device.deviceProtocol,
            speed: UInt8(device.speed.rawValue),
            manufacturerString: device.manufacturerString,
            productString: device.productString,
            serialNumberString: device.serialNumberString,
            locationID: UInt32((Int(device.busID) ?? 20) << 24) | UInt32(Int(device.deviceID) ?? 0)
        )
    }
    
    private func setupHappyPathScenario() {
        shouldFailServiceMatching = false
        shouldFailGetMatchingServices = false
        shouldFailNotificationPortCreate = false
        shouldFailAddNotification = false
        
        // All devices are claimable
        for i in 0..<mockDevices.count {
            let service = io_service_t(mockServiceValue + UInt32(i))
            makeDeviceClaimable(service: service)
        }
    }
    
    private func setupNoDevicesScenario() {
        mockDevices.removeAll()
        claimableDevices.removeAll()
    }
    
    private func setupNotificationFailureScenario() {
        shouldFailNotificationPortCreate = true
        shouldFailAddNotification = true
        addNotificationError = KERN_FAILURE
    }
    
    private func setupClaimingFailureScenario() {
        for i in 0..<mockDevices.count {
            let service = io_service_t(mockServiceValue + UInt32(i))
            makeDeviceClaimFail(service: service, error: KERN_PROTECTION_FAILURE)
        }
    }
    
    private func setupMixedResultsScenario() {
        for i in 0..<mockDevices.count {
            let service = io_service_t(mockServiceValue + UInt32(i))
            
            switch i % 3 {
            case 0:
                makeDeviceClaimable(service: service)
            case 1:
                makeDeviceAlreadyClaimed(service: service)
            case 2:
                makeDeviceClaimFail(service: service, error: KERN_PROTECTION_FAILURE)
            default:
                break
            }
        }
    }
}

// MARK: - Development Test Scenarios

/// Predefined test scenarios for development environment
public enum DevelopmentTestScenario {
    case happyPath          // All operations succeed
    case noDevicesFound     // No USB devices available
    case notificationFailure // Notification system fails
    case claimingFailure    // Device claiming fails
    case mixedResults       // Mix of success and failure conditions
}

// MARK: - Development Mock Statistics

/// Statistics structure for development environment mock verification
public struct DevelopmentMockStatistics {
    public let totalOperationCalls: Int
    public let deviceDiscoveryCalls: Int
    public let notificationCalls: Int
    public let deviceClaimAttempts: Int
    public let deviceReleaseAttempts: Int
    public let currentlyMockedDevices: Int
    public let operationTimings: [String: TimeInterval]
    
    public init(
        totalOperationCalls: Int,
        deviceDiscoveryCalls: Int,
        notificationCalls: Int,
        deviceClaimAttempts: Int,
        deviceReleaseAttempts: Int,
        currentlyMockedDevices: Int,
        operationTimings: [String: TimeInterval]
    ) {
        self.totalOperationCalls = totalOperationCalls
        self.deviceDiscoveryCalls = deviceDiscoveryCalls
        self.notificationCalls = notificationCalls
        self.deviceClaimAttempts = deviceClaimAttempts
        self.deviceReleaseAttempts = deviceReleaseAttempts
        self.currentlyMockedDevices = currentlyMockedDevices
        self.operationTimings = operationTimings
    }
}

// MARK: - MockUSBDevice Extension

extension MockUSBDevice {
    /// Convert to USBDevice for easier testing
    func toUSBDevice() -> USBDevice {
        return USBDevice(
            busID: "1",
            deviceID: String(locationID & 0xFF),
            vendorID: vendorID,
            productID: productID,
            deviceClass: deviceClass,
            deviceSubClass: deviceSubClass,
            deviceProtocol: deviceProtocol,
            speed: USBSpeed(rawValue: Int(speed)) ?? .full,
            manufacturerString: manufacturerString,
            productString: productString,
            serialNumberString: serialNumberString
        )
    }
}

// MARK: - USBDeviceTestFixtures Extension

extension USBDeviceTestFixtures {
    /// Convert test fixture to MockUSBDevice for IOKit mocking
    static func createMockUSBDevice(from fixture: MockUSBDevice) -> MockUSBDevice {
        return fixture
    }
}