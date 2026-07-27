import XCTest
@testable import Reach5

/// Le contrat réseau de `WebAuthnLoginRequest` : `dictionary()` (utilisé par `ReachFiveApi`) doit omettre
/// les champs non renseignés plutôt que les envoyer à `null`.
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
