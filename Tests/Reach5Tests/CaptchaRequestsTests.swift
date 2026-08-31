import XCTest
@testable import Reach5

/// Two things about the captcha are silent when they break.
///
/// Each of the six request models copies the token and the provider into its own pair of properties by
/// hand, and `CaptchaProvider`'s wire form comes from a conformance nothing in the type spells out.
final class CaptchaRequestsTests: XCTestCase {
    private let captcha = Captcha(token: "the-token", provider: .reCaptcha)

    /// One request per endpoint that accepts a captcha, named after that endpoint.
    private var requestsCarryingTheCaptcha: [(endpoint: String, dictionary: [String: Any]?)] {
        [
            ("password_login", LoginRequest(email: "user@example.com", phoneNumber: nil, customIdentifier: nil, password: "pwd", grantType: "password", clientId: "testclient", scope: "openid", captcha: captcha).dictionary()),
            ("signup_token", SignupRequest(clientId: "testclient", data: ProfileSignupRequest(password: "pwd", email: "user@example.com"), scope: "openid", redirectUrl: nil, captcha: captcha).dictionary()),
            ("forgot_password", RequestPasswordResetRequest(clientId: "testclient", email: "user@example.com", phoneNumber: nil, redirectUrl: nil, captcha: captcha).dictionary()),
            ("account_recovery", RequestAccountRecoveryRequest(clientId: "testclient", email: "user@example.com", captcha: captcha).dictionary()),
            ("passwordless", StartPasswordlessRequest(clientId: "testclient", email: "user@example.com", authType: .MagicLink, redirectUri: URL(string: "reachfive-testclient://callback")!, codeChallenge: "challenge", codeChallengeMethod: "S256", captcha: captcha).dictionary()),
            ("update_email", UpdateEmailRequest(email: "user@example.com", redirectUrl: nil, captcha: captcha).dictionary()),
        ]
    }

    /// The plumbing, model by model — including `StartPasswordlessRequest`, whose convenience initializer
    /// has to relay the captcha to the designated one.
    func testEveryRequestCarriesTheTokenAndTheProvider() {
        for (endpoint, dictionary) in requestsCarryingTheCaptcha {
            XCTAssertEqual(dictionary?["captcha_token"] as? String, "the-token", endpoint)
            XCTAssertEqual(dictionary?["captcha_provider"] as? String, "recaptcha", endpoint)
        }
    }

    /// No captcha means no key, not an empty one: the server reads these parameters through
    /// `optional(nonEmptyText)` mappings, which reject an empty value as a malformed request.
    func testNoCaptchaLeavesBothParametersOut() {
        let dictionary = LoginRequest(email: "user@example.com", phoneNumber: nil, customIdentifier: nil, password: "pwd", grantType: "password", clientId: "testclient", scope: "openid").dictionary()

        XCTAssertNotNil(dictionary, "the request did not encode at all")
        XCTAssertNil(dictionary?["captcha_token"])
        XCTAssertNil(dictionary?["captcha_provider"])
    }

    /// The provider travels as a bare name: the standard library's `RawRepresentable` conformance encodes
    /// the raw value itself, where a hand-written or memberwise `Codable` would wrap it in
    /// `{"rawValue": …}`. Nothing in `CaptchaProvider` says so, hence this test.
    func testTheProviderEncodesAsItsBareName() {
        XCTAssertEqual(dictionary(for: Captcha(token: "t", provider: .captchaFox))?["captcha_provider"] as? String, "captchafox")
    }

    /// The reason `CaptchaProvider` is not an enum: a name this version does not know must still reach the
    /// server untouched.
    func testAnUnknownProviderIsForwardedAsGiven() {
        XCTAssertEqual(dictionary(for: Captcha(token: "t", provider: CaptchaProvider(rawValue: "newcomer")))?["captcha_provider"] as? String, "newcomer")
    }

    private func dictionary(for captcha: Captcha) -> [String: Any]? {
        LoginRequest(email: "user@example.com", phoneNumber: nil, customIdentifier: nil, password: "pwd", grantType: "password", clientId: "testclient", scope: "openid", captcha: captcha).dictionary()
    }
}
