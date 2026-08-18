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
}
