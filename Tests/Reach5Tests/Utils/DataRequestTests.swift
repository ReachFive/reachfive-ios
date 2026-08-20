import XCTest
@testable import Reach5

/// What a failed decoding tells the integrator. Foundation's `localizedDescription` for a `DecodingError` is
/// a single generic sentence, translated into the device's language and naming neither the field nor the
/// problem, so `parseJson` used to turn a precisely located error into an unactionable one.
final class DataRequestTests: XCTestCase {

    private struct Payload: Decodable {
        struct Item: Decodable {
            let name: String
            let count: Int
        }
        let items: [Item]
    }

    private func reason(for json: String) -> String {
        do {
            _ = try JSONDecoder().decode(Payload.self, from: Data(json.utf8))
            XCTFail("'\(json)' was expected not to decode")
            return ""
        } catch {
            return DataRequest.reason(decoding: Payload.self, failedWith: error)
        }
    }

    func testTheOffendingFieldIsNamed() {
        let reason = reason(for: #"{"items":[{"name":"a","count":1},{"name":"b"}]}"#)

        XCTAssertTrue(reason.contains("items"), reason)
        // The index is what tells which element of the array is at fault.
        XCTAssertTrue(reason.contains("Index 1"), reason)
        XCTAssertTrue(reason.contains("count"), reason)
        XCTAssertTrue(reason.contains("Payload"), reason)
    }

    func testATypeMismatchSaysWhatWasExpected() {
        let reason = reason(for: #"{"items":[{"name":"a","count":"not a number"}]}"#)

        XCTAssertTrue(reason.contains("count"), reason)
        XCTAssertTrue(reason.contains("Int"), reason)
    }

    func testTheGenericLocalizedSentenceIsGone() {
        // The sentence itself is localized, so what is asserted is that the reason is not just it: a
        // `DecodingError` yields one of the cases above, all of which name a path.
        let reason = reason(for: #"{"items":[{"name":"a"}]}"#)

        XCTAssertTrue(reason.hasPrefix("Could not decode"), reason)
        XCTAssertTrue(reason.contains("at '"), reason)
    }

    func testANonDecodingErrorKeepsItsOwnDescription() {
        struct Elsewhere: LocalizedError {
            var errorDescription: String? { "the network went away" }
        }

        XCTAssertEqual(
            DataRequest.reason(decoding: Payload.self, failedWith: Elsewhere()),
            "the network went away")
    }
}
