import XCTest
@testable import Reach5

/// Covers `URL+Normalization`: what Foundation leaves undone on a parsed URL (`normalizedScheme`,
/// `normalizedHost`, `normalizedPath`, `isHttpBased`) and the origin built on top of it (`serializedOrigin`).
///
/// `normalizedScheme` and `normalizedHost` are depended on by `URL.serializedOrigin` below, on which
/// `SdkConfig.baseComponents` in turn rests, as well as by `SdkConfig.isValidCallbackUri` and
/// `URL.matchesEndpoint(of:)` — and each of their rules has already cost a bug when one of them got it wrong,
/// so they are pinned here rather than only through their callers.
final class URLNormalizationTests: XCTestCase {

    // MARK: - Scheme

    func testSchemeIsLowercased() {
        let cases: [(input: String, expected: String)] = [
            ("https://example.com", "https"), // already lower-case
            ("HTTPS://example.com", "https"), // upper-case
            // The default custom scheme is derived from the clientId, so it usually carries mixed case
            ("reachfive-AbC://callback", "reachfive-abc"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(URL(string: input)!.normalizedScheme, expected, "'\(input)'")
        }
    }

    func testSchemeIsNilWithoutOne() {
        XCTAssertNil(URL(string: "example.com")!.normalizedScheme)
    }

    // MARK: - Host

    func testHostIsLowercased() {
        XCTAssertEqual(URL(string: "https://AUTH.Example.COM")!.normalizedHost, "auth.example.com")
    }

    /// `URL.host` strips the brackets an IPv6 literal needs, both in a URL and in an origin.
    func testIPv6HostKeepsItsBrackets() {
        XCTAssertEqual(URL(string: "https://[::1]")!.normalizedHost, "[::1]")
        XCTAssertEqual(URL(string: "https://[2001:DB8::1]")!.normalizedHost, "[2001:db8::1]")
    }

    /// The distinction `URL.host` does not make: an authority with no host reads back as `""`, not `nil`.
    /// Both spellings build a URL that only fails later, on the network.
    func testHostlessAuthorityIsNilNotEmpty() {
        XCTAssertEqual(URL(string: "https://:8443")!.host, "", "précondition : Foundation renvoie bien \"\"")
        XCTAssertNil(URL(string: "https://:8443")!.normalizedHost)
        XCTAssertNil(URL(string: "https://[]")!.normalizedHost)
        XCTAssertNil(URL(string: "https://")!.normalizedHost)
    }

    func testOrdinaryHostsAreUnchanged() {
        for host in ["example.reach5.net", "localhost", "127.0.0.1", "xn--caf-dma.example"] {
            XCTAssertEqual(URL(string: "https://\(host)")!.normalizedHost, host)
        }
    }

    // MARK: - Path

    /// `normalizedPath` folds `"/"` onto `""` and nothing else, because `URL.path` has already dropped the
    /// trailing slash of a longer path. Both facts are load-bearing: the matcher and
    /// `SdkConfig.isValidCallbackUri` are written against them.
    func testNormalizedPath() {
        let cases: [(input: String, expected: String)] = [
            ("https://h/cb", "/cb"), // baseline
            ("https://h/cb/", "/cb"), // URL.path drops the trailing slash itself
            ("https://h/", ""), // the one case left to fold
            ("https://h", ""), // already empty
            ("com.example.app:/oauth2redirect", "/oauth2redirect"), // no authority: the path is all there is
            ("com.example.app:/", ""), // which is why this URI discriminates nothing
            ("com.example.app://callback", ""), // authority-only: the host carries the discrimination
            ("custom:opaque", ""), // Foundation gives an opaque part no path
        ]
        for (input, expected) in cases {
            XCTAssertEqual(URL(string: input)!.normalizedPath, expected, "'\(input)'")
        }
    }

    // MARK: - Scheme family

    /// The frontier the SDK's two callback channels are built on: an http(s) URI needs a naming authority and
    /// is delivered through `ASWebAuthenticationSession`'s universal-link callback, which requires a host;
    /// every other scheme is private-use and delivered through `callbackURLScheme:` or
    /// `application(_:open:)`, which look only at the scheme.
    func testIsHttpBased() {
        for scheme in ["http", "https", "HTTPS"] {
            XCTAssertTrue(URL(string: "\(scheme)://host/cb")!.isHttpBased, "'\(scheme)'")
        }
        for scheme in ["reachfive-abc", "com.example.app", "httpx-app", "mailto"] {
            XCTAssertFalse(URL(string: "\(scheme)://host/cb")!.isHttpBased, "'\(scheme)'")
        }
        XCTAssertFalse(URL(string: "example.com")!.isHttpBased, "no scheme at all")
    }

    // MARK: - Origin

    /// One representative per class of input, not an exhaustive sweep: each row teaches a distinct rule.
    /// Shared with `testOriginSerializationIsIdempotent`, which holds these same values to the invariant
    /// every origin the SDK emits must satisfy.
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
        // The host shapes `SdkConfig` accepts as a `domain`, since its fallback origin is built from them
        ("https://localhost", "https://localhost"), // a single label, no dot
        ("https://example.com.", "https://example.com."), // trailing-dot FQDN: the dot is origin-significant
        ("https://my_host.example", "https://my_host.example"), // not a legal DNS label, but it serializes
    ]

    func testAcceptableOrigins() {
        for (input, expected) in Self.acceptableOrigins {
            let url = URL(string: input)!
            XCTAssertEqual(url.serializedOrigin, expected, "'\(input)' should serialize to '\(expected)'")
        }
    }

    func testUnacceptableOrigins() {
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

    /// An origin the SDK produces must itself parse back to that same origin. WebURL's conformance harness
    /// holds every case it runs to this invariant, over and above the expected values, and it catches a class
    /// of regression a table of expectations cannot: a serializer that dropped the brackets of an IPv6 host,
    /// or restored a default port, would still satisfy every row above while emitting an origin that no
    /// longer round-trips — and what the server receives is the emitted string, not the row.
    func testOriginSerializationIsIdempotent() {
        for (input, _) in Self.acceptableOrigins {
            let url = URL(string: input)!
            guard let origin = url.serializedOrigin else {
                XCTFail("'\(input)' should serialize to an origin")
                continue
            }
            XCTAssertEqual(
                URL(string: origin)?.serializedOrigin, origin,
                "origin '\(origin)' does not survive being parsed and serialized again")
        }
    }
}
