import XCTest
@testable import Reach5

final class DataRequestRedirectTests: XCTestCase {
    // Held in a property rather than built inline: `NetworkClient.deinit` invalidates its session, which a
    // temporary dropped right after `.request(...)` would do before the request could run.
    private var networkClient: NetworkClient!

    override func setUp() {
        super.setUp()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        networkClient = NetworkClient(decoder: decoder, configuration: StubURLProtocol.makeSessionConfiguration())
    }

    override func tearDown() {
        networkClient = nil
        StubURLProtocol.stubHandler = nil
        super.tearDown()
    }

    /// The nominal outcome: the task ends on the redirection, refused rather than followed, and the callback
    /// is read from its `Location` header.
    func testRedirectionToTheCustomSchemeYieldsTheCallback() async throws {
        StubURLProtocol.stubHandler = { _ in .redirection(to: "reachfive-client://callback?code=abc123") }

        let url = try await authorize()

        XCTAssertEqual(url.absoluteString, "reachfive-client://callback?code=abc123")
    }

    /// RFC 3986 §3.1 makes the scheme case-insensitive, and the default one is derived from the clientId, so
    /// a callback can come back in a case the SDK never wrote.
    func testRedirectionToTheCustomSchemeInAnotherCaseSucceeds() async throws {
        StubURLProtocol.stubHandler = { _ in .redirection(to: "REACHFIVE-Client://callback?code=abc123") }

        let url = try await authorize()

        XCTAssertEqual(url.queryValue("code"), "abc123")
    }

    /// The failure the whole call used to swallow: the server refuses the request outright — a rejected
    /// `redirect_uri` answers `403 error.client.redirectUrlNotAllowed` — and the body says why.
    func testNoRedirectWithApiErrorBodyThrowsTechnicalErrorWithApiError() async throws {
        let body = #"{"error":"access_denied","error_message_key":"error.client.redirectUrlNotAllowed","error_description":"The redirect url is not allowed."}"#
        StubURLProtocol.stubHandler = { _ in .response(statusCode: 403, body: Data(body.utf8)) }

        let (reason, apiError) = try await technicalErrorFromAuthorize()

        XCTAssertEqual(reason, "Response with 403 error code")
        XCTAssertEqual(apiError?.error, "access_denied")
        XCTAssertEqual(apiError?.errorMessageKey, "error.client.redirectUrlNotAllowed")
        XCTAssertEqual(apiError?.errorDescription, "The redirect url is not allowed.")
    }

    /// A proxy, a WAF or a gateway answers HTML rather than an `ApiError`, or nothing at all. Decoding can
    /// only fail, and the status code is then the only thing left to report — it must not be lost with the
    /// decoding. Covers `validate`, so it holds for every call, not just this one.
    func testErrorBodyThatIsNotAnApiErrorStillReportsTheStatus() async throws {
        let bodies: [(status: Int, headers: [String: String], body: Data)] = [
            (502, ["Content-Type": "text/html"], Data("<html><body>Bad gateway</body></html>".utf8)),
            (403, [:], Data()),
        ]

        for stub in bodies {
            StubURLProtocol.stubHandler = { _ in
                .response(statusCode: stub.status, headers: stub.headers, body: stub.body)
            }

            let (reason, apiError) = try await technicalErrorFromAuthorize()

            XCTAssertEqual(reason, "Response with \(stub.status) error code")
            XCTAssertNil(apiError)
        }
    }

    /// A response that simply did not redirect, and redirections that lead anywhere but the app's custom
    /// scheme. None carries a callback nor an `ApiError` body, so the status and where it leads is all there
    /// is to report.
    func testResponsesThatDoNotRedirectToTheCustomSchemeReportWhereTheyLead() async throws {
        let cases: [(stub: StubURLProtocol.Stub, reason: String)] = [
            (.response(statusCode: 200),
             "Request did not redirect to the app's custom scheme: answered HTTP 200"),
            (.redirection(to: "https://proxy.example.com/blocked", statusCode: 303),
             "Request did not redirect to the app's custom scheme: answered HTTP 303 with Location 'https://proxy.example.com/blocked'"),
            (.response(statusCode: 302),
             "Request did not redirect to the app's custom scheme: answered HTTP 302 with no Location header"),
        ]

        for expected in cases {
            StubURLProtocol.stubHandler = { _ in expected.stub }

            let (reason, _) = try await technicalErrorFromAuthorize()

            XCTAssertEqual(reason, expected.reason)
        }
    }

    /// A network failure — the pinning refusing a certificate among them — comes back untouched.
    func testNetworkFailureIsRethrownUntouched() async throws {
        StubURLProtocol.stubHandler = { _ in .networkFailure(URLError(.secureConnectionFailed)) }

        let thrown = try await failureOfAuthorize()

        XCTAssertEqual((thrown as? URLError)?.code, .secureConnectionFailed)
    }

    // MARK: - Helpers

    private func authorize() async throws -> URL {
        try await networkClient.request(URL(string: "https://example.com/oauth/authorize")!).redirect()
    }

    /// The error `/oauth/authorize` threw. No test here can legitimately succeed instead: that would mean a
    /// callback was read out of a response that carries none.
    private func failureOfAuthorize(
        file: StaticString = #filePath, line: UInt = #line
    ) async throws -> Error {
        try await failure(file: file, line: line) { _ = try await self.authorize() }
    }

    private func technicalErrorFromAuthorize(
        file: StaticString = #filePath, line: UInt = #line
    ) async throws -> (reason: String, apiError: ApiError?) {
        let thrown = try await failureOfAuthorize(file: file, line: line)
        guard case ReachFiveError.TechnicalError(let reason, let apiError) = thrown else {
            XCTFail("expected a TechnicalError, got \(thrown)", file: file, line: line)
            throw thrown
        }
        return (reason, apiError)
    }

    private func failure(
        file: StaticString = #filePath, line: UInt = #line, of expression: () async throws -> Void
    ) async throws -> Error {
        do {
            try await expression()
        } catch {
            return error
        }
        XCTFail("the request should have failed", file: file, line: line)
        throw UnexpectedSuccess()
    }

    private struct UnexpectedSuccess: Error {}
}
