import XCTest
@testable import Reach5

final class StartPasswordlessRequestTests: XCTestCase {
    private func makeRequest(email: String? = nil, phoneNumber: String? = nil, data: PasswordlessSignupData? = nil) -> StartPasswordlessRequest {
        StartPasswordlessRequest(
            clientId: "testclient",
            email: email,
            phoneNumber: phoneNumber,
            authType: email != nil ? .MagicLink : .SMS,
            redirectUri: URL(string: "reachfive-testclient://callback")!,
            codeChallenge: "challenge",
            codeChallengeMethod: "S256",
            data: data
        )
    }

    func testWithoutDataThePayloadHasNoDataKey() throws {
        let payload = try XCTUnwrap(makeRequest(email: "john.doe@example.com").dictionary())

        XCTAssertNil(payload["data"])
        XCTAssertEqual(payload["email"] as? String, "john.doe@example.com")
    }

    func testDataIsSentNestedAndInSnakeCase() throws {
        let data = PasswordlessSignupData(
            givenName: "John",
            familyName: "Doe",
            customFields: ["loyalty_level": .int(3)],
            consents: ["newsletter": Consent(granted: true, consentType: "opt-in", date: "2026-10-27T10:00:00Z")]
        )

        let payload = try XCTUnwrap(makeRequest(email: "john.doe@example.com", data: data).dictionary())
        let sent = try XCTUnwrap(payload["data"] as? [String: Any])

        XCTAssertEqual(sent["given_name"] as? String, "John")
        XCTAssertEqual(sent["family_name"] as? String, "Doe")
        XCTAssertEqual((sent["custom_fields"] as? [String: Any])?["loyalty_level"] as? Int, 3)
        let newsletter = try XCTUnwrap((sent["consents"] as? [String: Any])?["newsletter"] as? [String: Any])
        XCTAssertEqual(newsletter["granted"] as? Bool, true)
        XCTAssertEqual(newsletter["consent_type"] as? String, "opt-in")
        XCTAssertNil(sent["middle_name"])
    }

    func testAnEmailInTheDataOfAnSmsStartIsSentAsIs() throws {
        let data = PasswordlessSignupData(email: "john.doe@example.com")

        let payload = try XCTUnwrap(makeRequest(phoneNumber: "+33612345678", data: data).dictionary())

        XCTAssertEqual(payload["phone_number"] as? String, "+33612345678")
        XCTAssertNil(payload["email"])
        XCTAssertEqual((payload["data"] as? [String: Any])?["email"] as? String, "john.doe@example.com")
    }
}
