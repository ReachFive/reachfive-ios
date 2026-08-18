import XCTest
@testable import Reach5

/// Documents what is acceptable as a domain/clientId/customScheme when initializing SdkConfig.
final class SdkConfigTests: XCTestCase {

    // MARK: - Domain

    /// One representative per class of input, not an exhaustive sweep: each row teaches a distinct rule.
    /// Shared with `testBothWebAuthnOriginPathsAgree` and `testOriginSerializationIsIdempotent`, which hold
    /// these same values to the invariants `originWebAuthn` rests on.
    private static let acceptableDomains = [
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

    func testAcceptableDomains() {
        for domain in Self.acceptableDomains {
            XCTAssertNotNil(
                SdkConfig.baseComponents(domain: domain),
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
            "[]",                          // empty IPv6 literal: builds 'https://[]', whose host reads back empty
        ]
        for domain in unacceptable {
            XCTAssertNil(
                SdkConfig.baseComponents(domain: domain),
                "domain '\(domain)' should be rejected")
        }
    }

    /// `normalizedDomain` must fold exactly like `originWebAuthn`'s default fallback, since both come from
    /// the same validated components — a mismatch here would mean the two silently disagree on the same host.
    func testNormalizedDomainFoldsLikeTheDefaultWebAuthnOrigin() {
        for domain in Self.acceptableDomains {
            let config = SdkConfig(domain: domain, clientId: "abc")

            XCTAssertEqual(
                "https://\(config.normalizedDomain)", config.originWebAuthn,
                "normalizedDomain and originWebAuthn disagree on domain '\(domain)'")
        }
    }

    func testNormalizedDomainLowercasesAndBracketsTheHost() {
        XCTAssertEqual(SdkConfig(domain: "Example.Reach5.NET", clientId: "abc").normalizedDomain, "example.reach5.net")
        XCTAssertEqual(SdkConfig(domain: "[::1]", clientId: "abc").normalizedDomain, "[::1]")
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

    /// The clientId is deliberately mixed-case: the derived scheme must lowercase it, since a scheme is
    /// case-insensitive (RFC 3986 §3.1) and every comparison against an incoming callback assumes the
    /// lower-cased form
    func testDefaultUrisAreDerivedFromClientId() {
        let config = SdkConfig(domain: "example.reach5.net", clientId: "9DKRdQyDLpaJqQQQAR9K")

        XCTAssertEqual(config.customScheme, "reachfive-9dkrdqydlpajqqqqar9k")
        XCTAssertEqual(config.redirectUri.absoluteString, "reachfive-9dkrdqydlpajqqqqar9k://callback")
        XCTAssertEqual(config.mfaUri.absoluteString, "reachfive-9dkrdqydlpajqqqqar9k://mfa")
        XCTAssertEqual(config.emailVerificationUri.absoluteString, "reachfive-9dkrdqydlpajqqqqar9k://email-verification")
        XCTAssertEqual(config.accountRecoveryUri.absoluteString, "reachfive-9dkrdqydlpajqqqqar9k://account-recovery")
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
            XCTAssertTrue(
                SdkConfig.isValidScheme("reachfive-\(clientId)"),
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
            XCTAssertFalse(
                SdkConfig.isValidScheme("reachfive-\(clientId)"),
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
            XCTAssertTrue(
                SdkConfig.isValidScheme(scheme),
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
            XCTAssertFalse(
                SdkConfig.isValidScheme(scheme),
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

    /// An explicit URI may legitimately use a scheme and host that have nothing to do with `customScheme` —
    /// a universal link redirect on the integrator's own domain, for instance — so only "has both a scheme
    /// and a host" is checked, the two `matchesEndpoint(of:)` compares an incoming callback against.
    func testAcceptableExplicitUris() {
        let acceptable = [
            "https://example.com/callback",        // universal link, unrelated to customScheme
            "com.example.app://mfa",                // a different custom scheme than the derived default
            "reachfive-abc://callback",              // the shape of the default itself
            "https://example.com",                  // no path: matchesEndpoint treats "" and "/" the same
        ]
        for uri in acceptable {
            XCTAssertTrue(
                SdkConfig.isValidCallbackUri(URL(string: uri)!),
                "'\(uri)' should be acceptable")
        }
    }

    func testUnacceptableExplicitUris() {
        let unacceptable = [
            "not-a-url",              // no scheme, no host: parses as a relative reference
            "//example.com/callback", // scheme-relative: a host, but no scheme
            "reachfive-abc:///path",  // a scheme, but an empty authority: no host
            "reachfive-abc://",       // a scheme, no authority at all: no host
            "custom:opaque",         // a scheme with an opaque part, no authority: no host
        ]
        for uri in unacceptable {
            XCTAssertFalse(
                SdkConfig.isValidCallbackUri(URL(string: uri)!),
                "'\(uri)' should be rejected")
        }
    }

    // MARK: - WebAuthn origin

    func testWebAuthnOriginDefaultsToTheDomain() {
        let config = SdkConfig(domain: "example.reach5.net", clientId: "abc")

        XCTAssertEqual(config.originWebAuthn, "https://example.reach5.net")
    }

    /// `domain` is validated at init but kept as given, so it can still carry mixed case. RFC 6454 origins
    /// must be lower-case, so the fold happens here, at the point of use.
    func testWebAuthnOriginDefaultLowercasesTheDomain() {
        let config = SdkConfig(domain: "Example.Reach5.NET", clientId: "abc")

        XCTAssertEqual(config.originWebAuthn, "https://example.reach5.net")
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

        XCTAssertEqual(fromDomain.originWebAuthn, "https://xn--caf-dma.example")
        XCTAssertEqual(fromDomain.originWebAuthn, configured.originWebAuthn)
        // The very host the API requests go to, so the server sees a consistent pair
        XCTAssertEqual(fromDomain.baseUrlComponents.url?.host, "xn--caf-dma.example")
    }

    /// An IPv6 domain is valid (`testAcceptableDomains` covers it) and needs the brackets an origin requires,
    /// which a bare `"https://\(domain)"` interpolation would not add back.
    func testWebAuthnOriginDefaultBracketsAnIPv6Domain() {
        XCTAssertEqual(SdkConfig(domain: "[::1]", clientId: "abc").originWebAuthn, "https://[::1]")
    }

    func testConfiguredOriginWins() {
        let config = SdkConfig(
            domain: "example.reach5.net",
            clientId: "abc",
            originWebAuthn: URL(string: "https://auth.example.com")!)

        XCTAssertEqual(config.originWebAuthn, "https://auth.example.com")
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

        XCTAssertEqual(withTrailingSlash.originWebAuthn, "https://auth.example.com")
        XCTAssertEqual(withPath.originWebAuthn, "https://auth.example.com")
    }

    func testNonDefaultPortIsKept() {
        let config = SdkConfig(
            domain: "example.reach5.net",
            clientId: "abc",
            originWebAuthn: URL(string: "https://localhost:8443")!)

        XCTAssertEqual(config.originWebAuthn, "https://localhost:8443")
    }

    /// One representative per class of input, like `acceptableDomains`. Shared with
    /// `testOriginSerializationIsIdempotent`.
    private static let acceptableOrigins: [(input: String, expected: String)] = [
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

    /// Same style as `testAcceptableClientIds`/`testAcceptableCustomSchemes`: goes through
    /// `URL.serializedOrigin` directly, the single construction point the init's precondition relies
    /// on, so a malformed input can be checked without crashing the test process.
    func testAcceptableWebAuthnOrigins() {
        for (input, expected) in Self.acceptableOrigins {
            let url = URL(string: input)!
            XCTAssertEqual(url.serializedOrigin, expected, "'\(input)' should serialize to '\(expected)'")
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
            // `URL.host` percent-*decodes*, so these read back as the hosts "a b.example" and "a/b.example".
            // Interpolating those would emit an origin carrying a raw space, or one whose slash reads as a
            // path; reassembling through URLComponents refuses them instead.
            "https://a%20b.example",
            "https://a%2Fb.example",
        ]
        for input in unacceptable {
            let url = URL(string: input)!
            XCTAssertNil(url.serializedOrigin, "'\(input)' should be rejected")
        }
    }

    // MARK: - Invariants held over the tables above

    /// The two ways into `originWebAuthn` — the `domain` fallback and a configured `originWebAuthn` — must
    /// never disagree on the same host, since a request carries one or the other and the server sees no
    /// difference. `testWebAuthnOriginDefaultUsesTheAsciiFormOfAnInternationalizedDomain` checks the one
    /// case where they nearly did; this holds the whole table to it.
    func testBothWebAuthnOriginPathsAgree() {
        for domain in Self.acceptableDomains {
            let fromDomain = SdkConfig(domain: domain, clientId: "abc")
            let configured = SdkConfig(
                domain: "example.reach5.net",
                clientId: "abc",
                originWebAuthn: URL(string: "https://\(domain)")!)

            XCTAssertEqual(
                fromDomain.originWebAuthn, configured.originWebAuthn,
                "the two paths disagree on domain '\(domain)'")
        }
    }

    /// An origin the SDK produces must itself parse back to that same origin. WebURL's conformance harness
    /// holds every case it runs to this invariant, over and above the expected values, and it catches a class
    /// of regression a table of expectations cannot: a serializer that dropped the brackets of an IPv6 host,
    /// or restored a default port, would still satisfy every row above while emitting an origin that no
    /// longer round-trips — and what the server receives is the emitted string, not the row.
    func testOriginSerializationIsIdempotent() {
        let urls = Self.acceptableDomains.compactMap { SdkConfig.baseComponents(domain: $0)?.components.url }
            + Self.acceptableOrigins.map { URL(string: $0.input)! }

        for url in urls {
            guard let origin = url.serializedOrigin else {
                XCTFail("'\(url)' should serialize to an origin")
                continue
            }
            XCTAssertEqual(
                URL(string: origin)?.serializedOrigin, origin,
                "origin '\(origin)' does not survive being parsed and serialized again")
        }
    }
}
