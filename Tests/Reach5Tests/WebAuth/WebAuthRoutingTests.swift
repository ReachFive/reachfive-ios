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
        XCTAssertFalse(routing(state: "abc").matches(URL(string: "https://host.example.com/cb?state=zzz")!))
    }

    func testMatchesRegardlessOfURL() {
        // Le state fait foi : un host/path différent n'empêche pas le match.
        XCTAssertTrue(routing(state: "abc").matches(URL(string: "https://elsewhere.example.com/whatever?state=abc")!))
    }

    func testNoStateReturnsFalse() {
        // Sans `state` dans le callback, aucune session ne matche.
        XCTAssertFalse(routing(state: "abc").matches(URL(string: "https://host.example.com/cb?code=x")!))
    }

    func testNoQueryReturnsFalse() {
        XCTAssertFalse(routing(state: "abc").matches(URL(string: "https://host.example.com/cb")!))
    }

    func testStateIsCaseSensitive() {
        XCTAssertFalse(routing(state: "AbC").matches(URL(string: "https://host.example.com/cb?state=abc")!))
    }

    func testStateMatchIsExactNotPrefixNorContains() {
        XCTAssertFalse(routing(state: "abc").matches(URL(string: "https://host.example.com/cb?state=abcd")!))
        XCTAssertFalse(routing(state: "abc").matches(URL(string: "https://host.example.com/cb?state=ab")!))
        XCTAssertFalse(routing(state: "abc").matches(URL(string: "https://host.example.com/cb?state=xabcx")!))
    }

    func testEmptyReturnedStateDoesNotMatchNonEmpty() {
        XCTAssertFalse(routing(state: "abc").matches(URL(string: "https://host.example.com/cb?state=")!))
    }

    func testStateAmongManyParams() {
        XCTAssertTrue(routing(state: "abc").matches(URL(string: "https://host.example.com/cb?a=1&state=abc&b=2")!))
    }

    func testPercentEncodedStateMatches() {
        // state contenant un espace ; le callback le porte percent-encodé (%20).
        XCTAssertTrue(routing(state: "a b").matches(URL(string: "https://host.example.com/cb?state=a%20b")!))
    }

    func testRealisticUUIDState() {
        let uuid = "C0FFEE00-1234-5678-9ABC-DEF012345678"
        XCTAssertTrue(routing(state: uuid).matches(URL(string: "https://host.example.com/cb?code=x&state=\(uuid)")!))
    }
}
