import XCTest
@testable import Reach5

final class UsernameTests: XCTestCase {
    func testUnspecifiedIsSplitByTheAtSign() {
        XCTAssertEqual(Username.Unspecified("jane@example.com").identifiers.email, "jane@example.com")
        XCTAssertNil(Username.Unspecified("jane@example.com").identifiers.phoneNumber)

        XCTAssertEqual(Username.Unspecified("+33600000000").identifiers.phoneNumber, "+33600000000")
        XCTAssertNil(Username.Unspecified("+33600000000").identifiers.email)
    }

    func testExplicitIdentifiersAreCarriedAsIs() {
        XCTAssertEqual(Username.Email("jane@example.com").identifiers.email, "jane@example.com")
        XCTAssertNil(Username.Email("jane@example.com").identifiers.phoneNumber)

        XCTAssertEqual(Username.PhoneNumber("+33600000000").identifiers.phoneNumber, "+33600000000")
        XCTAssertNil(Username.PhoneNumber("+33600000000").identifiers.email)
    }
}
