import XCTest
@testable import Reach5

/// Documents what is acceptable as a domain/clientId/customScheme when initializing SdkConfig.
///
/// The default scheme is derived from the clientId as `reachfive-<clientId>`, so the clientId
/// obeys the same rules as a scheme: it must contain only letters, digits, `+`, `-` or `.`.
/// An invalid scheme stops the program with a `preconditionFailure` at init, which cannot be
/// asserted directly in XCTest: the invalid cases below go through `SdkConfig.baseUrlComponents(domain:)`
/// and `SdkConfig.makeUri`, the single construction points on which the init's precondition relies.
final class SdkConfigTests: XCTestCase {

    // MARK: - Domain

    func testAcceptableDomains() {
        let acceptable = [
            "example.reach5.net",   // baseline
            "Example.Reach5.NET",   // mixed case: DNS is case-insensitive, and the value is kept as given
            "my-tenant.reach5.net", // hyphen
            "localhost",            // a single label, no dot
            "127.0.0.1",            // IPv4 literal
            "[::1]",                // IPv6 literal: URLComponents requires the brackets
            "café.example",         // non-ASCII: Foundation punycodes the host when it builds each request
            "example.com.",         // trailing-dot FQDN: legitimate, and the dot is origin-significant
            "my_host.example",      // not a legal DNS label, but the URL builds: only DNS can reject it
            "x..example",           // same — an empty label is a DNS problem, not a parsing one
        ]
        for domain in acceptable {
            XCTAssertNotNil(
                SdkConfig.baseUrlComponents(domain: domain),
                "domain '\(domain)' should be acceptable")
        }
    }

    func testUnacceptableDomains() {
        let unacceptable = [
            "https://example.reach5.net",  // a scheme: the domain is a bare host, not a URL
            "example.reach5.net/",         // trailing slash
            "example.reach5.net/identity", // path
            "example.reach5.net:8443",     // port — createUrl never sets one, honouring it is impossible
            "user@example.reach5.net",     // userinfo
            "example.reach5.net?a=b",      // query
            "example.reach5.net#anchor",   // fragment
            "example reach5.net",          // whitespace
            " example.reach5.net",         // leading whitespace, e.g. a copy-paste
            "::1",                         // IPv6 literal without its brackets
            "",                            // empty: would build a host-less 'https:///path'
        ]
        for domain in unacceptable {
            XCTAssertNil(
                SdkConfig.baseUrlComponents(domain: domain),
                "domain '\(domain)' should be rejected")
        }
    }

    func testBaseUrlComponentsCarryOnlySchemeAndHost() {
        let config = SdkConfig(domain: "example.reach5.net", clientId: "abc")

        XCTAssertEqual(config.baseUrlComponents.scheme, "https")
        XCTAssertEqual(config.baseUrlComponents.host, "example.reach5.net")
        XCTAssertEqual(config.baseUrlComponents.path, "")
        XCTAssertNil(config.baseUrlComponents.port)
        XCTAssertNil(config.baseUrlComponents.queryItems)
    }

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

    /// `domain` is validated at init but kept as given, so it can still carry mixed case. RFC 6454 origins
    /// must be lower-case, so the fold happens here, at the point of use.
    func testWebAuthnOriginDefaultLowercasesTheDomain() {
        let config = SdkConfig(domain: "Example.Reach5.NET", clientId: "abc")

        XCTAssertEqual(config.webAuthnOrigin, "https://example.reach5.net")
    }

    /// The `domain` fallback and a configured origin go through the same serializer, so they cannot disagree
    /// on a host that needs normalizing. An internationalized domain is where they would: RFC 6454 §6.2 ASCII
    /// Serialization expects the host in its A-label form, whereas returning `café.example` verbatim is the
    /// §6.1 *Unicode* serialization — a different algorithm. The A-label form is also the host `createUrl`
    /// sends every API request to, since both start from `baseUrlComponents`.
    func testWebAuthnOriginDefaultUsesTheAsciiFormOfAnInternationalizedDomain() {
        let fromDomain = SdkConfig(domain: "café.example", clientId: "abc")
        let configured = SdkConfig(
            domain: "example.reach5.net",
            clientId: "abc",
            originWebAuthn: URL(string: "https://café.example")!)

        XCTAssertEqual(fromDomain.webAuthnOrigin, "https://xn--caf-dma.example")
        XCTAssertEqual(fromDomain.webAuthnOrigin, configured.webAuthnOrigin)
        // The very host the API requests go to, so the server sees a consistent pair
        XCTAssertEqual(fromDomain.baseUrlComponents.url?.host, "xn--caf-dma.example")
    }

    /// An IPv6 domain is valid (`testAcceptableDomains` covers it) and needs the brackets an origin requires,
    /// which a bare `"https://\(domain)"` interpolation would not add back.
    func testWebAuthnOriginDefaultBracketsAnIPv6Domain() {
        XCTAssertEqual(SdkConfig(domain: "[::1]", clientId: "abc").webAuthnOrigin, "https://[::1]")
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
            "https://:8443", // an authority with a port but no host: URL.host is "", not nil
            "https://@:8443", // userinfo and port, still no host
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
