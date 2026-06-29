import XCTest
@testable import Reach5

final class WebAuthRoutingTests: XCTestCase {

    private func routing(state: String = "abc", callback: String? = "https://host.example.com/cb") -> WebAuthRouting {
        WebAuthRouting(state: state, expectedCallback: callback.flatMap { URL(string: $0) })
    }

    func testMatchesByState() {
        XCTAssertTrue(routing(state: "abc").matches(URL(string: "https://host.example.com/cb?code=x&state=abc")!))
    }

    func testRejectsDifferentState() {
        XCTAssertFalse(routing(state: "abc").matches(URL(string: "https://host.example.com/cb?code=x&state=zzz")!))
    }

    func testMatchesRegardlessOfURL() {
        // Le state fait foi : un host/path différent n'empêche pas le match.
        XCTAssertTrue(routing(state: "abc", callback: "https://host.example.com/cb")
            .matches(URL(string: "https://elsewhere.example.com/whatever?state=abc")!))
    }

    func testNoStateReturnsFalse() {
        // Sans `state` dans le callback, aucune session ne matche.
        XCTAssertFalse(routing(state: "abc").matches(URL(string: "https://host.example.com/cb?code=x")!))
    }
}
