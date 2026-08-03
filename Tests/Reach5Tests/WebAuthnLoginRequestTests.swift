import XCTest
@testable import Reach5

/// `WebAuthnLoginRequest`'s wire contract: `dictionary()` must omit the fields left unset rather than
/// send them as `null`.
final class WebAuthnLoginRequestTests: XCTestCase {
    func testEmailIdentifierIsSentAloneInSnakeCase() throws {
        let dict = try XCTUnwrap(WebAuthnLoginRequest(clientId: "testclient", origin: "https://example.reach5.net", username: .Email("jane@example.com")).dictionary())

        XCTAssertEqual(dict["client_id"] as? String, "testclient")
        XCTAssertEqual(dict["email"] as? String, "jane@example.com")
        XCTAssertNil(dict["phone_number"])
    }

    func testWithoutUsernameNoIdentifierIsSent() throws {
        let dict = try XCTUnwrap(WebAuthnLoginRequest(clientId: "testclient", origin: "https://example.reach5.net").dictionary())

        XCTAssertNil(dict["email"])
        XCTAssertNil(dict["phone_number"])
    }
}
