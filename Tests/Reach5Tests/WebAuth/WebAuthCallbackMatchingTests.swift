import XCTest
@testable import Reach5

/// Reconnaissance « est-ce notre callback ? » par forme d'URL (host + path + présence d'un `code`).
final class WebAuthCallbackMatchingTests: XCTestCase {

    private func isOurs(_ incoming: String, expected: String) -> Bool {
        WebAuthenticationSession.isOurCallback(URL(string: incoming)!, expectedCallback: URL(string: expected)!)
    }

    func testMatchesSameHostPathWithCode() {
        XCTAssertTrue(isOurs("https://host.example.com/cb?code=abc&state=x", expected: "https://host.example.com/cb"))
    }

    func testRejectsMissingCode() {
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
}
