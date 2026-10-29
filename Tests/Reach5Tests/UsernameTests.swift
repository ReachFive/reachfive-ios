import XCTest
@testable import Reach5

final class UsernameTests: XCTestCase {
    func testUnspecifiedIsSplitByTheAtSign() {
        XCTAssertEqual(Username.unspecified("jane@example.com").email, "jane@example.com")
        XCTAssertNil(Username.unspecified("jane@example.com").phoneNumber)

        XCTAssertEqual(Username.unspecified("+33600000000").phoneNumber, "+33600000000")
        XCTAssertNil(Username.unspecified("+33600000000").email)
    }

    func testExplicitIdentifiersAreCarriedAsIs() {
        XCTAssertEqual(Username.Email("jane@example.com").email, "jane@example.com")
        XCTAssertNil(Username.Email("jane@example.com").phoneNumber)

        XCTAssertEqual(Username.PhoneNumber("+33600000000").phoneNumber, "+33600000000")
        XCTAssertNil(Username.PhoneNumber("+33600000000").email)
    }
}
