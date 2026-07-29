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

    // MARK: - WebAuthn origin

    func testWebAuthnOriginDefaultsToTheDomain() {
        let config = SdkConfig(domain: "example.reach5.net", clientId: "abc")

        XCTAssertEqual(config.webAuthnOrigin, "https://example.reach5.net")
    }

    /// `domain` is a free-form, unvalidated `String`, unlike `originWebAuthn`. Mixed case is the one
    /// malformation that stays valid everywhere else in the SDK (DNS is case-insensitive) yet still needs
    /// folding here, since RFC 6454 origins must be lower-case.
    func testWebAuthnOriginDefaultLowercasesTheDomain() {
        let config = SdkConfig(domain: "Example.Reach5.NET", clientId: "abc")

        XCTAssertEqual(config.webAuthnOrigin, "https://example.reach5.net")
    }

    func testConfiguredOriginWins() {
        let config = SdkConfig(
            domain: "example.reach5.net",
            clientId: "abc",
            originWebAuthn: URL(string: "https://auth.example.com")!)

        XCTAssertEqual(config.webAuthnOrigin, "https://auth.example.com")
    }

    /// An origin is a scheme, a host and a non-default port — nothing else. `absoluteString` would keep the
    /// path and the trailing slash, which the server and the system both reject; hence the normalization.
    func testTrailingSlashAndPathAreStripped() {
        let withTrailingSlash = SdkConfig(
            domain: "example.reach5.net",
            clientId: "abc",
            originWebAuthn: URL(string: "https://auth.example.com/")!)
        let withPath = SdkConfig(
            domain: "example.reach5.net",
            clientId: "abc",
            originWebAuthn: URL(string: "https://auth.example.com/webauthn")!)

        XCTAssertEqual(withTrailingSlash.webAuthnOrigin, "https://auth.example.com")
        XCTAssertEqual(withPath.webAuthnOrigin, "https://auth.example.com")
    }

    func testNonDefaultPortIsKept() {
        let config = SdkConfig(
            domain: "example.reach5.net",
            clientId: "abc",
            originWebAuthn: URL(string: "https://localhost:8443")!)

        XCTAssertEqual(config.webAuthnOrigin, "https://localhost:8443")
    }

    /// Same style as `testAcceptableClientIds`/`testAcceptableCustomSchemes`: goes through
    /// `SdkConfig.serializedOrigin` directly, the single construction point the init's precondition relies
    /// on, so a malformed input can be checked without crashing the test process.
    func testAcceptableWebAuthnOrigins() {
        let acceptable: [(input: String, expected: String)] = [
            ("https://auth.example.com", "https://auth.example.com"), // baseline
            ("https://auth.example.com/", "https://auth.example.com"), // trailing slash stripped
            ("https://auth.example.com/webauthn/register", "https://auth.example.com"), // path stripped
            ("https://auth.example.com?client=abc", "https://auth.example.com"), // query stripped
            ("https://auth.example.com#fragment", "https://auth.example.com"), // fragment stripped
            ("https://user:pass@auth.example.com", "https://auth.example.com"), // userinfo dropped
            ("HTTPS://auth.example.com", "https://auth.example.com"), // scheme is lowercased
            ("https://localhost:8443", "https://localhost:8443"), // non-default port is kept
            ("https://auth.example.com:443", "https://auth.example.com"), // default https port is stripped
            ("http://auth.example.com:80", "http://auth.example.com"), // default http port is stripped
            ("https://127.0.0.1:9000", "https://127.0.0.1:9000"), // IPv4 host, kept as-is
            ("https://[::1]:8443", "https://[::1]:8443"), // IPv6 literal: URL.host drops the brackets, put them back
            ("https://AUTH.EXAMPLE.COM", "https://auth.example.com"), // host is lowercased, like the WHATWG domain parser does
            ("https://[2001:DB8::1]", "https://[2001:db8::1]"), // IPv6 hex digits are lowercased too
            ("https://café.example", "https://xn--caf-dma.example"), // IDNA: Foundation already punycode-encodes non-ASCII hosts
        ]
        for (input, expected) in acceptable {
            let url = URL(string: input)!
            XCTAssertEqual(SdkConfig.serializedOrigin(url), expected, "'\(input)' should serialize to '\(expected)'")
        }
    }

    func testUnacceptableWebAuthnOrigins() {
        let unacceptable = [
            "auth.example.com", // no scheme: parses as a relative reference
            "//auth.example.com", // scheme-relative: no scheme
            "https://", // scheme but no host
            "https:///webauthn", // scheme and a path, still no host
            "mailto:test@example.com", // has a scheme, but no host
            "file:///path/to/file", // has a scheme, but no host
        ]
        for input in unacceptable {
            let url = URL(string: input)!
            XCTAssertNil(SdkConfig.serializedOrigin(url), "'\(input)' should be rejected")
        }
    }
}
