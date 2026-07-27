import XCTest
@testable import Reach5

/// Reconnaissance « est-ce notre callback ? » par forme d'URL (scheme + host + path + présence d'un `code` ou d'un `error`).
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
        // Même host et path, mais un scheme https ne doit pas matcher un callback attendu en custom scheme
        // (et inversement) : c'est ce qui sépare les deux canaux hors-bande.
        XCTAssertFalse(isOurs("https://callback/?code=abc", expected: "reachfive-clientId://callback"))
        XCTAssertFalse(isOurs("reachfive-clientId://callback?code=abc", expected: "https://callback/"))
    }
}
