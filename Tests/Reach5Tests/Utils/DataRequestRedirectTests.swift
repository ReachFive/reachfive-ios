import XCTest
@testable import Reach5

final class DataRequestRedirectTests: XCTestCase {
    // `NetworkClient.deinit` invalidates its session, so it must outlive the awaited `redirect()` call —
    // a temporary dropped right after `.request(...)` would invalidate the session before the task runs.
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

    func testRedirectToPrivateSchemeSucceeds() async throws {
        StubURLProtocol.stubHandler = { _ in
            .redirect(to: "reachfive-client://callback?code=abc123")
        }

        let url = try await networkClient
            .request(URL(string: "https://example.com/oauth/authorize")!)
            .redirect()

        XCTAssertEqual(url.absoluteString, "reachfive-client://callback?code=abc123")
    }

    func testNoRedirectWithApiErrorBodyThrowsTechnicalErrorWithApiError() async {
        let body = #"{"error":"access_denied","error_message_key":"error.client.redirectUrlNotAllowed","error_description":"The redirect url is not allowed."}"#.data(using: .utf8)!
        StubURLProtocol.stubHandler = { _ in
            .response(statusCode: 403, body: body)
        }

        do {
            _ = try await networkClient
                .request(URL(string: "https://example.com/oauth/authorize")!)
                .redirect()
            XCTFail("attendu : une erreur")
        } catch let ReachFiveError.TechnicalError(reason, apiError) {
            XCTAssertEqual(reason, "Response with 403 error code")
            XCTAssertEqual(apiError?.error, "access_denied")
            XCTAssertEqual(apiError?.errorMessageKey, "error.client.redirectUrlNotAllowed")
            XCTAssertEqual(apiError?.errorDescription, "The redirect url is not allowed.")
        } catch {
            XCTFail("attendu : ReachFiveError.TechnicalError, obtenu \(error)")
        }
    }

    func testNetworkErrorDuringRedirectIsRethrownUnchanged() async {
        StubURLProtocol.stubHandler = { _ in
            .networkFailure(URLError(.networkConnectionLost))
        }

        do {
            _ = try await networkClient
                .request(URL(string: "https://example.com/oauth/authorize")!)
                .redirect()
            XCTFail("attendu : une erreur")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .networkConnectionLost)
        } catch {
            XCTFail("attendu : URLError, obtenu \(error)")
        }
    }

    /// A network interception layer that answers the redirection itself instead of forwarding it to the SDK
    /// delegate leaves `URLSession` to follow it — and loading a private scheme can only fail with
    /// `unsupportedURL`. The callback, authorization code included, is in the failing URL: the SDK recovers it.
    func testRedirectionFollowedInsteadOfInterceptedRecoversTheCallback() async throws {
        let callback = URL(string: "reachfive-client://callback?code=abc123")!
        StubURLProtocol.stubHandler = { _ in
            .networkFailure(NSError(domain: NSURLErrorDomain, code: NSURLErrorUnsupportedURL, userInfo: [
                NSURLErrorFailingURLErrorKey: callback,
            ]))
        }

        let url = try await networkClient
            .request(URL(string: "https://example.com/oauth/authorize")!)
            .redirect()

        XCTAssertEqual(url, callback)
    }

    /// Same recovery when the error only carries the failing URL as a string.
    func testRedirectionFollowedRecoversTheCallbackFromTheFailingUrlString() async throws {
        StubURLProtocol.stubHandler = { _ in
            .networkFailure(NSError(domain: NSURLErrorDomain, code: NSURLErrorUnsupportedURL, userInfo: [
                NSURLErrorFailingURLStringErrorKey: "reachfive-client://callback?code=abc123",
            ]))
        }

        let url = try await networkClient
            .request(URL(string: "https://example.com/oauth/authorize")!)
            .redirect()

        XCTAssertEqual(url.absoluteString, "reachfive-client://callback?code=abc123")
    }

    /// `unsupportedURL` on an http URL is a genuine failure, not a callback: it must not be mistaken for one.
    func testUnsupportedUrlOnAnHttpUrlIsStillAnError() async {
        StubURLProtocol.stubHandler = { _ in
            .networkFailure(NSError(domain: NSURLErrorDomain, code: NSURLErrorUnsupportedURL, userInfo: [
                NSURLErrorFailingURLErrorKey: URL(string: "https://example.com/oauth/authorize")!,
            ]))
        }

        do {
            _ = try await networkClient
                .request(URL(string: "https://example.com/oauth/authorize")!)
                .redirect()
            XCTFail("attendu : une erreur")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .unsupportedURL)
        } catch {
            XCTFail("attendu : URLError, obtenu \(error)")
        }
    }

    /// A delegate other than the SDK's refusing the redirection ends the task on the redirect response
    /// itself. Its `Location` header still carries the callback: the SDK reads it there.
    func testRedirectionRefusedBeforeTheSdkSeesItRecoversTheCallback() async throws {
        StubURLProtocol.stubHandler = { _ in
            .refusedRedirection(to: "reachfive-client://callback?code=abc123")
        }

        let url = try await networkClient
            .request(URL(string: "https://example.com/oauth/authorize")!)
            .redirect()

        XCTAssertEqual(url.absoluteString, "reachfive-client://callback?code=abc123")
    }

    /// Neither a redirection, nor a response, nor an error is not something an HTTP exchange produces: only
    /// something answering for `URLSession` can. The SDK says so rather than failing opaquely.
    func testCompletionWithoutResponseNorErrorNamesTheInterception() async {
        StubURLProtocol.stubHandler = { _ in .finishWithoutResponse() }

        do {
            _ = try await networkClient
                .request(URL(string: "https://example.com/oauth/authorize")!)
                .redirect()
            XCTFail("attendu : une erreur")
        } catch let ReachFiveError.TechnicalError(reason, apiError) {
            XCTAssertTrue(reason.contains("without a response nor an error"), reason)
            XCTAssertNil(apiError)
        } catch {
            XCTFail("attendu : ReachFiveError.TechnicalError, obtenu \(error)")
        }
    }

    /// A 2xx that never redirects carries no `ApiError` to decode: the status is all the SDK can report, and
    /// reporting it is what tells an integrator the redirection never happened at all.
    func testSuccessfulResponseWithoutRedirectionReportsTheStatus() async {
        StubURLProtocol.stubHandler = { _ in .response(statusCode: 200) }

        do {
            _ = try await networkClient
                .request(URL(string: "https://example.com/oauth/authorize")!)
                .redirect()
            XCTFail("attendu : une erreur")
        } catch let ReachFiveError.TechnicalError(reason, _) {
            XCTAssertEqual(reason, "Request did not redirect as expected: answered 200 HTTP status instead of a redirection to the private scheme")
        } catch {
            XCTFail("attendu : ReachFiveError.TechnicalError, obtenu \(error)")
        }
    }

    // MARK: - Pinning refusing the connection

    /// The pinning doing its job — a certificate that does not match. `URLSession` reports it as an ordinary
    /// error and the SDK must let it through untouched: dressing it up would hide a real security refusal.
    func testRejectedCertificateIsRethrownUntouched() async {
        StubURLProtocol.stubHandler = { _ in
            .networkFailure(URLError(.secureConnectionFailed))
        }

        do {
            _ = try await networkClient
                .request(URL(string: "https://example.com/oauth/authorize")!)
                .redirect()
            XCTFail("attendu : une erreur")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .secureConnectionFailed)
        } catch {
            XCTFail("attendu : URLError, obtenu \(error)")
        }
    }

    /// Same, when the pinning answers the authentication challenge with `cancelAuthenticationChallenge`:
    /// `URLSession` turns it into a plain cancellation, which must not be mistaken for a user cancellation
    /// nor swallowed by any of the recoveries.
    func testCancelledAuthenticationChallengeIsRethrownUntouched() async {
        StubURLProtocol.stubHandler = { _ in
            .networkFailure(URLError(.cancelled))
        }

        do {
            _ = try await networkClient
                .request(URL(string: "https://example.com/oauth/authorize")!)
                .redirect()
            XCTFail("attendu : une erreur")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
        } catch {
            XCTFail("attendu : URLError, obtenu \(error)")
        }
    }

    // MARK: - Interception leading the redirection elsewhere

    /// An interception layer rewriting the redirection towards its own block page: the target is not the
    /// private scheme, so it is no callback. The error says where it actually leads.
    func testRedirectionRewrittenToAnHttpTargetIsNotTakenForACallback() async {
        StubURLProtocol.stubHandler = { _ in
            .refusedRedirection(to: "https://proxy.example.com/blocked")
        }

        do {
            _ = try await networkClient
                .request(URL(string: "https://example.com/oauth/authorize")!)
                .redirect()
            XCTFail("attendu : une erreur")
        } catch let ReachFiveError.TechnicalError(reason, _) {
            XCTAssertEqual(reason, "Request did not redirect as expected: answered a 303 redirection to 'https://proxy.example.com/blocked', not to the private scheme the SDK intercepts")
        } catch {
            XCTFail("attendu : ReachFiveError.TechnicalError, obtenu \(error)")
        }
    }

    /// A redirection stripped of its `Location` — nothing to recover, and no `ApiError` body to decode
    /// either. The status and the missing header are all the SDK can report, so it reports them.
    func testRedirectionWithoutLocationReportsWhatIsMissing() async {
        StubURLProtocol.stubHandler = { _ in .response(statusCode: 302) }

        do {
            _ = try await networkClient
                .request(URL(string: "https://example.com/oauth/authorize")!)
                .redirect()
            XCTFail("attendu : une erreur")
        } catch let ReachFiveError.TechnicalError(reason, _) {
            XCTAssertEqual(reason, "Request did not redirect as expected: answered a 302 redirection to nowhere — no Location header, not to the private scheme the SDK intercepts")
        } catch {
            XCTFail("attendu : ReachFiveError.TechnicalError, obtenu \(error)")
        }
    }
}
