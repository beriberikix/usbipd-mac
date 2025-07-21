import XCTest
@testable import USBIPDCore

final class USBIPProtocolTests: XCTestCase {
    func testProtocolVersion() {
        XCTAssertEqual(USBIPProtocol.version, 0x0111, "Protocol version should be 1.1.1")
    }
    
    // TODO: Add more protocol tests
}