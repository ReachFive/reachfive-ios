import XCTest
@testable import Reach5

final class DataRequestRedirectTests: XCTestCase {
    // Held in a property rather than built inline: `NetworkClient.deinit` invalidates its session, which a
    // temporary dropped right after `.request(...)` would do before `responseJson()` could run. `redirect()`
    // only reads that session's configuration, and runs its task on its own, but the rule is the same one.
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
    /// is read from its `Location` header. Whoever refused it — the SDK's own delegate or an interception
    /// layer answering in its place — leaves the same thing behind, so a single path covers both.
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

    /// A response that simply did not redirect, and three redirections that lead anywhere but the app's
    /// custom scheme: an interception layer rewriting the target to its own block page, and one stripped of
    /// its `Location`. None carries a callback, and none carries an `ApiError` body either, so the status —
    /// and where it actually leads — is all the SDK can report.
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

    // MARK: - Recovering the callback when the redirection was followed

    /// A network interception layer that answers the redirection itself instead of forwarding it to the SDK
    /// delegate may let `URLSession` follow it — and loading the app's custom scheme can only fail with
    /// `unsupportedURL`. The callback, authorization code included, is in the failing URL: the SDK recovers
    /// it, whether the error carries it as a `URL` or as a string.
    func testRedirectionFollowedInsteadOfRefusedRecoversTheCallback() async throws {
        let callback = "reachfive-client://callback?code=abc123"
        let keys: [String: Any] = [
            NSURLErrorFailingURLErrorKey: URL(string: callback)!,
            NSURLErrorFailingURLStringErrorKey: callback,
        ]

        for (key, value) in keys {
            StubURLProtocol.stubHandler = { _ in
                .networkFailure(NSError(domain: NSURLErrorDomain, code: NSURLErrorUnsupportedURL, userInfo: [key: value]))
            }

            let url = try await authorize()

            XCTAssertEqual(url.absoluteString, callback, "recovering from \(key)")
        }
    }

    /// Every error that carries no callback must come back untouched, rather than a recovery inventing a URL
    /// or dressing the error up. Two of these are the pinning doing its job — a certificate that does not
    /// match, and an authentication challenge it answered with `cancelAuthenticationChallenge`, which
    /// `URLSession` turns into a plain cancellation. The last two are an `unsupportedURL` that is a genuine
    /// failure: on an http URL, and with no failing URL at all.
    func testErrorsThatCarryNoCallbackAreRethrownUntouched() async throws {
        let errors: [(error: Error, code: URLError.Code)] = [
            (URLError(.networkConnectionLost), .networkConnectionLost),
            (URLError(.secureConnectionFailed), .secureConnectionFailed),
            (URLError(.cancelled), .cancelled),
            (NSError(domain: NSURLErrorDomain, code: NSURLErrorUnsupportedURL, userInfo: [
                NSURLErrorFailingURLErrorKey: URL(string: "https://example.com/oauth/authorize")!,
            ]), .unsupportedURL),
            (NSError(domain: NSURLErrorDomain, code: NSURLErrorUnsupportedURL, userInfo: [:]), .unsupportedURL),
        ]

        for expected in errors {
            StubURLProtocol.stubHandler = { _ in .networkFailure(expected.error) }

            let thrown = try await failureOfAuthorize()

            guard let urlError = thrown as? URLError else {
                return XCTFail("expected a URLError, got \(thrown)")
            }
            XCTAssertEqual(urlError.code, expected.code)
        }
    }

    // MARK: - A task ending with neither a response nor an error

    /// Not something an HTTP exchange produces: only something answering for `URLSession` can.
    /// `URLSession.data(for:)` traps on that outcome, which is why the SDK does not use it. Asserted on
    /// `/oauth/authorize` and on an ordinary call alike, since every request goes through the same guard.
    func testCompletionWithoutResponseNorErrorIsReportedOnEveryCall() async throws {
        StubURLProtocol.stubHandler = { _ in .finishWithoutResponse() }

        let (redirectReason, apiError) = try await technicalErrorFromAuthorize()
        XCTAssertEqual(redirectReason, "Request ended without a response nor an error")
        XCTAssertNil(apiError)

        let ordinary = try await failure {
            try await self.networkClient.request(URL(string: "https://example.com/identity/v1/logout")!).responseJson()
        }
        guard case ReachFiveError.TechnicalError(let reason, _) = ordinary else {
            return XCTFail("expected a TechnicalError, got \(ordinary)")
        }
        XCTAssertEqual(reason, "Request ended without a response nor an error")
    }

    // MARK: - Cancellation

    /// Cancelling the calling `Task` must cancel the request, which is what `URLSession.data(for:)` did
    /// through its own cancellation handler. A continuation over `dataTask(with:completionHandler:)` drops
    /// that unless it is wired back, and the request would then run to `URLSession`'s 60 s timeout instead.
    func testCancellingTheCallingTaskCancelsTheRequest() async throws {
        StubURLProtocol.stubHandler = { _ in .neverAnswers() }

        let request = Task { try await self.authorize() }
        // Long enough for the task to have started, short enough that a dropped cancellation shows up as a
        // test that never finishes rather than one that passes.
        try await Task.sleep(nanoseconds: 200_000_000)
        request.cancel()

        do {
            _ = try await request.value
            XCTFail("the request should have been cancelled")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
        }
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
