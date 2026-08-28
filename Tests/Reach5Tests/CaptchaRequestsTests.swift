import XCTest
@testable import Reach5

/// Six endpoints accept a captcha token, each with its own request model, and all six encode it the
/// same way: two flat parameters, `captcha_token` and `captcha_provider`. Everything past that
/// encoding goes to the network, so these tests pin the encoding itself.
///
/// The absent case matters as much as the present one: the server reads these parameters through
/// `optional(nonEmptyText)` form mappings, for which a key holding an empty value is not the same
/// thing as no key at all.
final class CaptchaRequestsTests: XCTestCase {
    private let captcha = Captcha(token: "the-token", provider: .reCaptcha)

    /// The keys the server expects, for a request that carries a captcha.
    private func assertCarriesTheCaptcha(_ dictionary: [String: Any]?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(dictionary?["captcha_token"] as? String, "the-token", file: file, line: line)
        XCTAssertEqual(dictionary?["captcha_provider"] as? String, "recaptcha", file: file, line: line)
    }

    /// No captcha means no key, not an empty one.
    private func assertOmitsTheCaptcha(_ dictionary: [String: Any]?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(dictionary, "the request did not encode at all", file: file, line: line)
        XCTAssertNil(dictionary?["captcha_token"], file: file, line: line)
        XCTAssertNil(dictionary?["captcha_provider"], file: file, line: line)
    }

    // MARK: - password_login

    private func loginRequest(captcha: Captcha?) -> LoginRequest {
        LoginRequest(email: "user@example.com", phoneNumber: nil, customIdentifier: nil, password: "pwd", grantType: "password", clientId: "testclient", scope: "openid", captcha: captcha)
    }

    func testLoginRequestCarriesTheCaptcha() {
        assertCarriesTheCaptcha(loginRequest(captcha: captcha).dictionary())
    }

    func testLoginRequestOmitsTheCaptchaWhenThereIsNone() {
        assertOmitsTheCaptcha(loginRequest(captcha: nil).dictionary())
    }

    // MARK: - signup_token

    private func signupRequest(captcha: Captcha?) -> SignupRequest {
        SignupRequest(clientId: "testclient", data: ProfileSignupRequest(password: "pwd", email: "user@example.com"), scope: "openid", redirectUrl: nil, captcha: captcha)
    }

    func testSignupRequestCarriesTheCaptcha() {
        assertCarriesTheCaptcha(signupRequest(captcha: captcha).dictionary())
    }

    func testSignupRequestOmitsTheCaptchaWhenThereIsNone() {
        assertOmitsTheCaptcha(signupRequest(captcha: nil).dictionary())
    }

    // MARK: - forgot_password

    private func passwordResetRequest(captcha: Captcha?) -> RequestPasswordResetRequest {
        RequestPasswordResetRequest(clientId: "testclient", email: "user@example.com", phoneNumber: nil, redirectUrl: nil, captcha: captcha)
    }

    func testPasswordResetRequestCarriesTheCaptcha() {
        assertCarriesTheCaptcha(passwordResetRequest(captcha: captcha).dictionary())
    }

    func testPasswordResetRequestOmitsTheCaptchaWhenThereIsNone() {
        assertOmitsTheCaptcha(passwordResetRequest(captcha: nil).dictionary())
    }

    private func accountRecoveryRequest(captcha: Captcha?) -> RequestAccountRecoveryRequest {
        RequestAccountRecoveryRequest(clientId: "testclient", email: "user@example.com", captcha: captcha)
    }

    func testAccountRecoveryRequestCarriesTheCaptcha() {
        assertCarriesTheCaptcha(accountRecoveryRequest(captcha: captcha).dictionary())
    }

    func testAccountRecoveryRequestOmitsTheCaptchaWhenThereIsNone() {
        assertOmitsTheCaptcha(accountRecoveryRequest(captcha: nil).dictionary())
    }

    // MARK: - passwordless

    private func startPasswordlessRequest(captcha: Captcha?) -> StartPasswordlessRequest {
        StartPasswordlessRequest(clientId: "testclient", email: "user@example.com", authType: .MagicLink, redirectUri: URL(string: "reachfive-testclient://callback")!, codeChallenge: "challenge", codeChallengeMethod: "S256", captcha: captcha)
    }

    func testStartPasswordlessRequestCarriesTheCaptcha() {
        assertCarriesTheCaptcha(startPasswordlessRequest(captcha: captcha).dictionary())
    }

    func testStartPasswordlessRequestOmitsTheCaptchaWhenThereIsNone() {
        assertOmitsTheCaptcha(startPasswordlessRequest(captcha: nil).dictionary())
    }

    // MARK: - update_email

    func testUpdateEmailRequestCarriesTheCaptcha() {
        assertCarriesTheCaptcha(UpdateEmailRequest(email: "user@example.com", redirectUrl: nil, captcha: captcha).dictionary())
    }

    func testUpdateEmailRequestOmitsTheCaptchaWhenThereIsNone() {
        assertOmitsTheCaptcha(UpdateEmailRequest(email: "user@example.com", redirectUrl: nil).dictionary())
    }

    // MARK: - CaptchaProvider

    /// The provider travels as a bare name. `Codable` synthesis would have wrapped a
    /// `RawRepresentable` struct in a `{"rawValue": …}` object, hence the hand-written coding.
    func testTheProviderEncodesAsItsBareName() {
        XCTAssertEqual(loginRequest(captcha: Captcha(token: "t", provider: .captchaFox)).dictionary()?["captcha_provider"] as? String, "captchafox")
    }

    /// A provider this version does not know must still reach the server: the SDK is not the place
    /// that decides which captcha services exist.
    func testAnUnknownProviderIsForwardedAsGiven() {
        XCTAssertEqual(loginRequest(captcha: Captcha(token: "t", provider: CaptchaProvider(rawValue: "newcomer"))).dictionary()?["captcha_provider"] as? String, "newcomer")
    }

    /// `.convertToSnakeCase` is what produces the wire names, so a rename of the Swift properties
    /// would silently change them.
    func testTheWireNamesAreSnakeCase() {
        let dictionary = loginRequest(captcha: captcha).dictionary()
        XCTAssertNil(dictionary?["captchaToken"])
        XCTAssertNil(dictionary?["captchaProvider"])
    }
}
