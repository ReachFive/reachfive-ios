import XCTest
@testable import Reach5

/// A network failure reaches the SDK as a `URLError`, which is not a `ReachFiveError`. Letting it
/// through breaks the documented contract, and crashes the `Reach5Future` bridge, which converts the
/// failure into a `Future<T, ReachFiveError>`.
final class DataRequestErrorTests: XCTestCase {

    private static let transportFailure = URLError(.notConnectedToInternet)

    /// Fails every request the way `URLSession` does when the device is offline.
    private final class OfflineProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}
        override func startLoading() {
            client?.urlProtocol(self, didFailWithError: DataRequestErrorTests.transportFailure)
        }
    }

    private func offlineRequest() -> DataRequest {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineProtocol.self]
        return DataRequest(
            request: URLRequest(url: URL(string: "https://sandbox.reach5.net/identity/v1/config")!),
            session: URLSession(configuration: configuration),
            redirectHandler: RedirectHandler(),
            decoder: JSONDecoder()
        )
    }

    private func assertOffline(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
        guard let error = error as? ReachFiveError else {
            return XCTFail("expected a ReachFiveError, got \(type(of: error))", file: file, line: line)
        }
        guard case let .TechnicalError(reason, apiError) = error else {
            return XCTFail("expected a TechnicalError, got \(error)", file: file, line: line)
        }
        XCTAssertEqual(reason, Self.transportFailure.localizedDescription, file: file, line: line)
        XCTAssertNil(apiError, file: file, line: line)
    }

    func testDecodedResponseReportsTransportFailureAsReachFiveError() async {
        do {
            _ = try await offlineRequest().responseJson(type: ClientConfigResponse.self)
            XCTFail("the request must fail")
        } catch {
            assertOffline(error)
        }
    }

    func testEmptyResponseReportsTransportFailureAsReachFiveError() async {
        do {
            try await offlineRequest().responseJson()
            XCTFail("the request must fail")
        } catch {
            assertOffline(error)
        }
    }

    func testWrappingLeavesAReachFiveErrorUntouched() {
        let original = ReachFiveError.AuthFailure(reason: "Unauthorized")
        guard case let .AuthFailure(reason, _) = ReachFiveError.wrapping(original) else {
            return XCTFail("an AuthFailure must come back as itself")
        }
        XCTAssertEqual(reason, "Unauthorized")
    }
}
