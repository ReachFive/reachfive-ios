import XCTest
@testable import Reach5

/// Documents how `ReachFive.originWebAuthn(overriddenBy:)` resolves the origin a passkey request must
/// carry: the request's own `originWebAuthn` when it sets one, `SdkConfig.originWebAuthn` otherwise.
///
/// It lives on `ReachFive` rather than on `SdkConfig` because an override is runtime data, not
/// configuration: it throws where the init's checks stop the program.
final class OriginWebAuthnOverrideTests: XCTestCase {

    private let reachFive = ReachFive(sdkConfig: SdkConfig(domain: "example.reach5.net", clientId: "abc"))

    /// A request that sets no origin falls back on the configured one.
    func testNoOverrideFallsBackOnTheConfiguredOrigin() throws {
        XCTAssertEqual(try reachFive.originWebAuthn(overriddenBy: nil), "https://example.reach5.net")
    }

    /// An override is normalized exactly like the configured value — same serializer, so the two can never
    /// send two spellings of the same host. Each row is a normalization the raw string would have skipped.
    func testOverrideIsNormalizedLikeTheConfiguredOrigin() throws {
        let cases: [(input: String, expected: String)] = [
            ("https://auth.example.com", "https://auth.example.com"),   // baseline
            ("https://auth.example.com/", "https://auth.example.com"),  // trailing slash stripped
            ("https://AUTH.Example.COM", "https://auth.example.com"),   // case folded
            ("https://café.example", "https://xn--caf-dma.example"),    // A-label form
            ("https://auth.example.com:443", "https://auth.example.com"), // default port dropped
            ("https://localhost:8443", "https://localhost:8443"),       // non-default port kept
        ]
        for (input, expected) in cases {
            XCTAssertEqual(try reachFive.originWebAuthn(overriddenBy: input), expected, "'\(input)'")
        }
    }

    /// An override that is not an origin throws instead of reaching the server, which would only reject it
    /// with an opaque error. It throws rather than crashing: unlike the config, this is runtime data.
    func testInvalidOverrideThrows() {
        let invalid = [
            "auth.example.com",     // no scheme
            "https://",             // scheme but no host
            "https://:8443",        // a port but no host
            "mailto:a@b.example",   // a scheme, but no host
            "",                     // empty
            "pas une url",          // whitespace: does not even parse
        ]
        for override in invalid {
            XCTAssertThrowsError(try reachFive.originWebAuthn(overriddenBy: override), "'\(override)' should be rejected") { error in
                guard case let ReachFiveError.TechnicalError(reason, _) = error else {
                    return XCTFail("attendu : TechnicalError, obtenu \(error)")
                }
                XCTAssertTrue(reason.contains("is not a valid WebAuthn origin"), "le message doit énoncer la règle")
                // `contains("")` is false, so the empty case can only be checked on the rule above
                if !override.isEmpty {
                    XCTAssertTrue(reason.contains(override), "le message doit citer la valeur fautive")
                }
            }
        }
    }
}
