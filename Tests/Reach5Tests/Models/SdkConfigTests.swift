import XCTest
@testable import Reach5

/// Documents what is acceptable as a clientId/customScheme when initializing SdkConfig.
///
/// The default scheme is derived from the clientId as `reachfive-<clientId>`, so the clientId
/// obeys the same rules as a scheme: it must contain only letters, digits, `+`, `-` or `.`.
/// An invalid scheme stops the program with a `preconditionFailure` at init, which cannot be
/// asserted directly in XCTest: the invalid cases below go through `SdkConfig.makeUri`,
/// the single construction point on which the init's precondition relies.
final class SdkConfigTests: XCTestCase {

    // MARK: - Acceptable clientIds

    func testDefaultUrisAreDerivedFromClientId() {
        let config = SdkConfig(domain: "example.reach5.net", clientId: "9DKRdQyDLpaJqQQQAR9K")

        XCTAssertEqual(config.customScheme, "reachfive-9DKRdQyDLpaJqQQQAR9K")
        XCTAssertEqual(config.redirectUri.absoluteString, "reachfive-9DKRdQyDLpaJqQQQAR9K://callback")
        XCTAssertEqual(config.mfaUri.absoluteString, "reachfive-9DKRdQyDLpaJqQQQAR9K://mfa")
        XCTAssertEqual(config.emailVerificationUri.absoluteString, "reachfive-9DKRdQyDLpaJqQQQAR9K://email-verification")
        XCTAssertEqual(config.accountRecoveryUri.absoluteString, "reachfive-9DKRdQyDLpaJqQQQAR9K://account-recovery")
    }

    func testAcceptableClientIds() {
        let acceptable = [
            "9DKRdQyDLpaJqQQQAR9K", // alphanumeric
            "abc",                  // letters only
            "123abc",               // may start with a digit: the derived scheme starts with 'reachfive-'
            "my-client",            // hyphen
            "my.client",            // dot
            "my+client",            // plus
        ]
        for clientId in acceptable {
            XCTAssertNotNil(
                SdkConfig.makeUri(scheme: "reachfive-\(clientId)", path: "callback"),
                "clientId '\(clientId)' should be acceptable")
        }
    }

    func testUnacceptableClientIds() {
        let unacceptable = [
            "my_client",  // underscore is not allowed in a URL scheme
            "my client",  // whitespace
            "my/client",  // slash
            "my:client",  // colon
            "my%client",  // percent
            "cliént",     // non-ASCII letter
        ]
        for clientId in unacceptable {
            XCTAssertNil(
                SdkConfig.makeUri(scheme: "reachfive-\(clientId)", path: "callback"),
                "clientId '\(clientId)' should be rejected")
        }
    }

    // MARK: - Acceptable customSchemes

    func testCustomSchemeOverridesTheDerivedScheme() {
        let config = SdkConfig(domain: "example.reach5.net", clientId: "my_client", customScheme: "com.example.app")

        XCTAssertEqual(config.customScheme, "com.example.app")
        XCTAssertEqual(config.redirectUri.absoluteString, "com.example.app://callback")
    }

    func testAcceptableCustomSchemes() {
        let acceptable = [
            "com.example.app", // reverse-DNS, the recommended form
            "a",               // single letter
            "myapp2",          // digits after the first letter
            "my-app+x.y",      // '+', '-' and '.' are allowed
        ]
        for scheme in acceptable {
            XCTAssertNotNil(
                SdkConfig.makeUri(scheme: scheme, path: "callback"),
                "customScheme '\(scheme)' should be acceptable")
        }
    }

    func testUnacceptableCustomSchemes() {
        let unacceptable = [
            "reachfive-my_client", // underscore
            "1app",                // must start with a letter
            "-app",                // must start with a letter
            "my app",              // whitespace
            "my:app",              // colon
            "my/app",              // slash
            "my?app",              // question mark
            "my#app",              // hash
            "",                    // empty
        ]
        for scheme in unacceptable {
            XCTAssertNil(
                SdkConfig.makeUri(scheme: scheme, path: "callback"),
                "customScheme '\(scheme)' should be rejected")
        }
    }

    // MARK: - Explicit URIs

    func testExplicitUrisAreKeptAsIs() {
        let redirectUri = URL(string: "https://example.com/callback")!
        let mfaUri = URL(string: "com.example.app://mfa")!
        let config = SdkConfig(
            domain: "example.reach5.net",
            clientId: "abc",
            redirectUri: redirectUri,
            mfaUri: mfaUri)

        XCTAssertEqual(config.redirectUri, redirectUri)
        XCTAssertEqual(config.mfaUri, mfaUri)
        // The other URIs still get their defaults
        XCTAssertEqual(config.accountRecoveryUri.absoluteString, "reachfive-abc://account-recovery")
        XCTAssertEqual(config.emailVerificationUri.absoluteString, "reachfive-abc://email-verification")
    }
}
