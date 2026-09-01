import XCTest
@testable import Reach5

/// The captcha section of `/identity/v1/config` is optional and may hold several configurations at
/// once — a client can have both providers active, and the server then requires both. These tests pin
/// the decoding of that contract, including the two cases that silently degrade an application:
/// a section the SDK fails to decode, and a provider name the SDK does not know.
final class ClientConfigCaptchaTests: XCTestCase {
    /// The decoder the API uses, snake_case included — `site_key` only becomes `siteKey` through it.
    private func decode(_ json: String) throws -> ClientConfigResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ClientConfigResponse.self, from: Data(json.utf8))
    }

    /// Every client today, and every client with no captcha tomorrow: the field is simply absent.
    func testAConfigurationWithoutCaptchaDecodesWithNone() throws {
        let config = try decode(#"{"scope": "openid profile", "sms": true}"#)

        XCTAssertNil(config.captcha)
        XCTAssertEqual(config.scope, "openid profile")
    }

    func testASingleConfigurationDecodesEveryField() throws {
        let config = try decode(#"""
        {
          "scope": "openid",
          "sms": false,
          "captcha": [
            {
              "provider": "recaptcha",
              "version": "v3",
              "site_key": "6Lexxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
              "endpoints": ["password_login", "signup_token"],
              "actions": ["login", "signup"]
            }
          ]
        }
        """#)

        let captcha = try XCTUnwrap(config.captcha?.first)
        XCTAssertEqual(captcha.provider, .reCaptcha)
        XCTAssertEqual(captcha.version, "v3")
        XCTAssertEqual(captcha.siteKey, "6Lexxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
        XCTAssertEqual(captcha.endpoints, ["password_login", "signup_token"])
        XCTAssertEqual(captcha.actions, ["login", "signup"])
    }

    /// Both providers active: the server runs every verifier and all of them must pass, so an
    /// application has to see both.
    func testTwoConfigurationsBothDecode() throws {
        let config = try decode(#"""
        {
          "scope": "openid",
          "sms": false,
          "captcha": [
            {"provider": "recaptcha", "site_key": "one", "endpoints": ["password_login"]},
            {"provider": "captchafox", "site_key": "two", "endpoints": ["signup_token"]}
          ]
        }
        """#)

        XCTAssertEqual(config.captcha?.map(\.provider), [.reCaptcha, .captchaFox])
        XCTAssertEqual(config.captcha?.map(\.siteKey), ["one", "two"])
    }

    /// A provider added on the server must not make the whole configuration undecodable — the reason
    /// `CaptchaProvider` is a struct rather than an enum, checked here on the decoding side.
    func testAProviderThisVersionDoesNotKnowStillDecodes() throws {
        let config = try decode(#"""
        {"scope": "openid", "sms": false, "captcha": [{"provider": "turnstile", "site_key": "k", "endpoints": []}]}
        """#)

        XCTAssertEqual(config.captcha?.first?.provider, CaptchaProvider(rawValue: "turnstile"))
    }

    /// An empty action list disables action validation server-side; an absent one means the same. The
    /// distinction between "no actions" and "all actions" is not the SDK's to invent.
    func testAbsentActionsDecodeAsNone() throws {
        let config = try decode(#"""
        {"scope": "openid", "sms": false, "captcha": [{"provider": "recaptcha", "site_key": "k", "endpoints": ["passwordless"]}]}
        """#)

        XCTAssertNil(config.captcha?.first?.actions)
        XCTAssertNil(config.captcha?.first?.version)
    }
}
