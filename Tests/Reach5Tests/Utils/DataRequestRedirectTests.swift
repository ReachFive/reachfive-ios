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

    func testCallbackIsReadFromTheLocationOfTheRedirectionThatEndsTheTask() async throws {
        StubURLProtocol.stubHandler = { _ in .redirection(to: "reachfive-client://callback?code=abc123") }

        let url = try await authorize()

        XCTAssertEqual(url.absoluteString, "reachfive-client://callback?code=abc123")
    }

    func testCallbackWhoseSchemeCaseDiffersFromTheOneSentIsStillRecognised() async throws {
        StubURLProtocol.stubHandler = { _ in .redirection(to: "REACHFIVE-Client://callback?code=abc123") }

        let url = try await authorize()

        XCTAssertEqual(url.queryValue("code"), "abc123")
    }

    func testRejectedRedirectUriThrowsTheApiErrorOfThe403Body() async throws {
        let body = #"{"error":"access_denied","error_message_key":"error.client.redirectUrlNotAllowed","error_description":"The redirect url is not allowed."}"#
        StubURLProtocol.stubHandler = { _ in .response(statusCode: 403, body: Data(body.utf8)) }

        let (reason, apiError) = try await technicalErrorFromAuthorize()

        XCTAssertEqual(reason, "Response with 403 error code")
        XCTAssertEqual(apiError?.error, "access_denied")
        XCTAssertEqual(apiError?.errorMessageKey, "error.client.redirectUrlNotAllowed")
        XCTAssertEqual(apiError?.errorDescription, "The redirect url is not allowed.")
    }

    func testErrorBodyThatIsNotAnApiErrorReportsTheStatus() async throws {
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

    func test401WithoutApiErrorBodyIsStillAnAuthFailure() async throws {
        StubURLProtocol.stubHandler = { _ in .response(statusCode: 401) }

        let thrown = try await failureOfAuthorize()

        guard case ReachFiveError.AuthFailure(_, let apiError) = thrown else {
            return XCTFail("expected an AuthFailure, got \(thrown)")
        }
        XCTAssertNil(apiError)
    }

    func testResponseThatDoesNotRedirectToTheCustomSchemeSaysWhereItLeads() async throws {
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

    func testNetworkFailureIsRethrownUntouched() async throws {
        StubURLProtocol.stubHandler = { _ in .networkFailure(URLError(.secureConnectionFailed)) }

        let thrown = try await failureOfAuthorize()

        XCTAssertEqual((thrown as? URLError)?.code, .secureConnectionFailed)
    }

    func testTaskEndingWithNeitherResponseNorErrorThrowsInsteadOfCrashingOnEveryCall() async throws {
        StubURLProtocol.stubHandler = { _ in .finishWithoutResponse }

        let (redirectReason, _) = try await technicalErrorFromAuthorize()
        XCTAssertEqual(redirectReason, "Request ended without a response nor an error")

        let ordinary = try await failure {
            try await self.networkClient.request(URL(string: "https://example.com/identity/v1/logout")!).responseJson()
        }
        guard case ReachFiveError.TechnicalError(let reason, _) = ordinary else {
            return XCTFail("expected a TechnicalError, got \(ordinary)")
        }
        XCTAssertEqual(reason, "Request ended without a response nor an error")
    }

    // MARK: - Helpers

    private func authorize() async throws -> URL {
        try await networkClient.request(URL(string: "https://example.com/oauth/authorize")!).redirect()
    }

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
