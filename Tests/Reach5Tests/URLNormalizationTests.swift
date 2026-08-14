import XCTest
@testable import Reach5

/// `normalizedScheme` and `normalizedHost` are the SDK's single answer to what Foundation leaves undone on a
/// parsed URL. Four places depend on them — `SdkConfig.serializedOrigin`, `SdkConfig.baseUrlComponents`,
/// `SdkConfig.makeUri` and `URL.matchesEndpoint(of:)` — and each of the three rules below has already cost a
/// bug when one of them got it wrong, so they are pinned here rather than only through their callers.
final class URLNormalizationTests: XCTestCase {

    // MARK: - Scheme

    func testSchemeIsLowercased() {
        let cases: [(input: String, expected: String)] = [
            ("https://example.com", "https"), // already lower-case
            ("HTTPS://example.com", "https"), // upper-case
            // The default custom scheme is derived from the clientId, so it usually carries mixed case —
            // exactly the shape that made loadLoginWebview miss its own callback.
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
}
