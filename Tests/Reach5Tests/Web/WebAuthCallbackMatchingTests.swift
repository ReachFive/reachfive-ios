import XCTest
@testable import Reach5

/// Recognizing "is this our callback?" by URL shape (scheme + host + path + presence of a `code` or an
/// `error`).
final class WebAuthCallbackMatchingTests: XCTestCase {

    private func isOurs(_ incoming: String, expected: String) -> Bool {
        WebAuthenticationSession.isOurCallback(URL(string: incoming)!, expectedCallback: URL(string: expected)!)
    }

    func testMatchesSameHostPathWithCode() {
        XCTAssertTrue(isOurs("https://host.example.com/cb?code=abc&state=x", expected: "https://host.example.com/cb"))
    }

    func testMatchesErrorCallback() {
        XCTAssertTrue(isOurs("https://host.example.com/cb?error=access_denied&state=x", expected: "https://host.example.com/cb"))
    }

    func testRejectsMissingCodeAndError() {
        XCTAssertFalse(isOurs("https://host.example.com/cb?state=x", expected: "https://host.example.com/cb"))
    }

    func testRejectsDifferentHost() {
        XCTAssertFalse(isOurs("https://evil.example.com/cb?code=abc", expected: "https://host.example.com/cb"))
    }

    func testHostIsCaseInsensitive() {
        XCTAssertTrue(isOurs("https://HOST.example.com/cb?code=abc", expected: "https://host.EXAMPLE.com/cb"))
    }

    func testRejectsDifferentPath() {
        XCTAssertFalse(isOurs("https://host.example.com/other?code=abc", expected: "https://host.example.com/cb"))
    }

    func testPathIsExactNotPrefix() {
        XCTAssertFalse(isOurs("https://host.example.com/cbextra?code=abc", expected: "https://host.example.com/cb"))
        XCTAssertFalse(isOurs("https://host.example.com/cb/sub?code=abc", expected: "https://host.example.com/cb"))
    }

    func testMatchesWithCodeAmongManyParams() {
        XCTAssertTrue(isOurs("https://host.example.com/cb?a=1&code=abc&b=2", expected: "https://host.example.com/cb"))
    }

    // MARK: Custom scheme (out-of-band via application(_:open:))

    func testMatchesCustomSchemeCallback() {
        XCTAssertTrue(isOurs("reachfive-clientId://callback?code=abc", expected: "reachfive-clientId://callback"))
    }

    func testSchemeIsCaseInsensitive() {
        XCTAssertTrue(isOurs("REACHFIVE-clientId://callback?code=abc", expected: "reachfive-clientId://callback"))
    }

    func testRejectsDifferentScheme() {
        // Same host and path, but an https scheme must not match a callback expected in a custom scheme
        // (and vice versa): that is what separates the two out-of-band channels.
        XCTAssertFalse(isOurs("https://callback/?code=abc", expected: "reachfive-clientId://callback"))
        XCTAssertFalse(isOurs("reachfive-clientId://callback?code=abc", expected: "https://callback/"))
    }

    // MARK: Private-use scheme without an authority (RFC 8252 §7.1)

    /// RFC 8252 §7.1 spells a private-use redirect URI with a single slash and no authority:
    /// `com.example.app:/oauth2redirect/example-provider`. Both hosts are then `nil`, and the paths carry
    /// the whole discrimination — which is why `SdkConfig` accepts this shape
    /// (`SdkConfigTests.testAcceptableExplicitUris`).
    func testMatchesAuthoritylessPrivateUseSchemeCallback() {
        XCTAssertTrue(isOurs("com.example.app:/oauth2redirect/example-provider?code=abc&state=x",
                              expected: "com.example.app:/oauth2redirect/example-provider"))
    }

    func testRejectsDifferentPathOnAnAuthoritylessCallback() {
        XCTAssertFalse(isOurs("com.example.app:/other?code=abc", expected: "com.example.app:/oauth2redirect"))
    }

    /// The trap this shape brings, and the reason the `preconditionFailure` message in `SdkConfig` spells it
    /// out: one slash and two are *different* endpoints. `com.example.app://callback` has the host
    /// `callback` and no path; `com.example.app:/callback` has no host and the path `/callback`. Declare
    /// one in the ReachFive console and pass the other and nothing ever matches — silently.
    func testAuthorityFormAndAuthoritylessFormAreDifferentEndpoints() {
        XCTAssertFalse(isOurs("com.example.app:/callback?code=abc", expected: "com.example.app://callback"))
        XCTAssertFalse(isOurs("com.example.app://callback?code=abc", expected: "com.example.app:/callback"))
    }

    /// The `"/"`-onto-`""` fold `normalizedPath` applies, on both shapes: a browser appends the trailing
    /// slash to an authority-only URL, and `URL.path` already drops it from a longer path.
    func testTrailingSlashStillMatches() {
        XCTAssertTrue(isOurs("com.example.app://callback/?code=abc", expected: "com.example.app://callback"))
        XCTAssertTrue(isOurs("com.example.app:/cb/?code=abc", expected: "com.example.app:/cb"))
    }
}
