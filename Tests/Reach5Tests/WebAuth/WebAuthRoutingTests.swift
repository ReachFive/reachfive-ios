import XCTest
@testable import Reach5

final class WebAuthRoutingTests: XCTestCase {

    private func routing(state: String = "abc", callback: String? = "https://host.example.com/cb") -> WebAuthRouting {
        WebAuthRouting(state: state, expectedCallback: callback.flatMap { URL(string: $0) })
    }

    // MARK: Routage par state (prioritaire)

    func testMatchesByState() {
        XCTAssertTrue(routing(state: "abc").matches(URL(string: "https://host.example.com/cb?code=x&state=abc")!))
    }

    func testRejectsDifferentState() {
        XCTAssertFalse(routing(state: "abc").matches(URL(string: "https://host.example.com/cb?code=x&state=zzz")!))
    }

    func testStateTakesPrecedenceOverURL() {
        // Même URL, mais le state diverge → refus (le state fait autorité).
        XCTAssertFalse(routing(state: "abc", callback: "https://host.example.com/cb")
            .matches(URL(string: "https://host.example.com/cb?state=other")!))
    }

    func testStateMatchEvenIfHostDiffers() {
        // Le state suffit : on ne regarde pas l'URL quand il est présent.
        XCTAssertTrue(routing(state: "abc", callback: "https://host.example.com/cb")
            .matches(URL(string: "https://elsewhere.example.com/whatever?state=abc")!))
    }

    // MARK: Fallback URL (state absent du callback)

    func testFallbackHostCaseInsensitive() {
        XCTAssertTrue(routing(state: "abc", callback: "https://Host.Example.com/cb")
            .matches(URL(string: "https://host.EXAMPLE.com/cb")!))
    }

    func testFallbackEmptyPathIsNotWildcard() {
        XCTAssertFalse(routing(state: "abc", callback: "https://host.example.com")
            .matches(URL(string: "https://host.example.com/anything")!))
    }

    func testFallbackRootPathIsNotWildcard() {
        XCTAssertFalse(routing(state: "abc", callback: "https://host.example.com/")
            .matches(URL(string: "https://host.example.com/promo")!))
    }

    func testFallbackNoOverMatchOnPartialSegment() {
        // "/cbextra" ne doit pas matcher "/cb" (comparaison par segments, pas hasPrefix).
        XCTAssertFalse(routing(state: "abc", callback: "https://host.example.com/cb")
            .matches(URL(string: "https://host.example.com/cbextra")!))
    }

    func testFallbackPathPrefixBySegments() {
        XCTAssertTrue(routing(state: "abc", callback: "https://host.example.com/cb")
            .matches(URL(string: "https://host.example.com/cb/return")!))
    }

    func testFallbackDifferentHost() {
        XCTAssertFalse(routing(state: "abc", callback: "https://host.example.com/cb")
            .matches(URL(string: "https://evil.example.com/cb")!))
    }

    func testFallbackNoExpectedCallback() {
        XCTAssertFalse(WebAuthRouting(state: "abc", expectedCallback: nil)
            .matches(URL(string: "https://host.example.com/cb")!))
    }
}
