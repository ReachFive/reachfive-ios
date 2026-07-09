import XCTest
@testable import Reach5

final class URLWebAuthTests: XCTestCase {

    func testQueryValuePresent() {
        XCTAssertEqual(URL(string: "https://h/p?code=abc&state=xyz")!.queryValue("state"), "xyz")
    }

    func testQueryValueAbsent() {
        XCTAssertNil(URL(string: "https://h/p?code=abc")!.queryValue("state"))
    }

    func testQueryValueNoQuery() {
        XCTAssertNil(URL(string: "https://h/p")!.queryValue("state"))
    }

    func testQueryValueEmptyValue() {
        XCTAssertEqual(URL(string: "https://h/p?state=")!.queryValue("state"), "")
    }

    func testQueryValuePercentDecoded() {
        XCTAssertEqual(URL(string: "https://h/p?state=a%20b")!.queryValue("state"), "a b")
    }

    func testQueryValueFirstOfDuplicates() {
        XCTAssertEqual(URL(string: "https://h/p?state=first&state=second")!.queryValue("state"), "first")
    }

    func testAuthorizationCodePresent() throws {
        XCTAssertEqual(try URL(string: "https://h/p?code=abc&state=x")!.authorizationCode(), "abc")
    }

    func testAuthorizationCodeMissingThrowsWithApiError() {
        XCTAssertThrowsError(try URL(string: "https://h/p?error=access_denied&error_description=denied")!.authorizationCode()) { error in
            guard case let ReachFiveError.TechnicalError(reason, apiError) = error else {
                return XCTFail("attendu : TechnicalError, obtenu \(error)")
            }
            XCTAssertEqual(reason, "No authorization code")
            XCTAssertEqual(apiError?.error, "access_denied")
        }
    }
}
