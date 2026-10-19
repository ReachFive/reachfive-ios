import XCTest
@testable import Reach5

/// `DataRequest.redirect()` run through `NetworkClient` against a real HTTP exchange on the loopback interface.
///
/// A `URLProtocol` stub cannot show what `URLSession` does with a redirection the session delegate refuses:
/// that the task ends on the 3xx itself, `Location` included, is not a documented contract, and every login
/// rests on it.
final class RedirectRefusalTests: XCTestCase {
    private var server: LoopbackHTTPServer!
    private var networkClient: NetworkClient!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        // Well under URLSession's 60 s default: a server that stops answering must fail the test, not stall
        // the whole suite on it.
        configuration.timeoutIntervalForRequest = 5
        networkClient = NetworkClient(decoder: JSONDecoder(), configuration: configuration)
    }

    override func tearDown() {
        server?.stop()
        server = nil
        networkClient = nil
        super.tearDown()
    }

    func testRedirectionToTheCustomSchemeIsRefusedAndYieldsTheCallback() async throws {
        server = try LoopbackHTTPServer { _ in
            "HTTP/1.1 302 Found\r\nLocation: reachfive-client://callback?code=abc123\r\nContent-Length: 0\r\n\r\n"
        }

        let callback = try await authorize()

        XCTAssertEqual(callback.absoluteString, "reachfive-client://callback?code=abc123")
    }

    func testWebRedirectionIsFollowedAndTheErrorNamesWhereItEnded() async throws {
        server = try LoopbackHTTPServer { requestLine in
            requestLine.contains("/oauth/authorize")
                ? "HTTP/1.1 302 Found\r\nLocation: /login\r\nContent-Length: 0\r\n\r\n"
                : "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}"
        }

        do {
            _ = try await authorize()
            XCTFail("the request should have failed")
        } catch ReachFiveError.TechnicalError(let reason, _) {
            XCTAssertEqual(
                reason,
                "Request did not redirect to its redirect_uri: answered HTTP 200 after redirecting to 'http://127.0.0.1:\(server.port)/login'"
            )
        }
    }

    func testRedirectionToAnHttpsRedirectUriIsRefusedAndYieldsTheCallback() async throws {
        server = try LoopbackHTTPServer { _ in
            "HTTP/1.1 302 Found\r\nLocation: https://www.example.com/account/callback?code=abc123\r\nContent-Length: 0\r\n\r\n"
        }

        let callback = try await authorize(redirectUri: "https://www.example.com/account/callback")

        XCTAssertEqual(callback.absoluteString, "https://www.example.com/account/callback?code=abc123")
    }

    func testWebRedirectionOtherThanTheRedirectUriIsStillFollowed() async throws {
        server = try LoopbackHTTPServer { requestLine in
            requestLine.contains("/oauth/authorize")
                ? "HTTP/1.1 302 Found\r\nLocation: /login\r\nContent-Length: 0\r\n\r\n"
                : "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}"
        }

        do {
            _ = try await authorize(redirectUri: "https://www.example.com/account/callback")
            XCTFail("the request should have failed")
        } catch ReachFiveError.TechnicalError(let reason, _) {
            XCTAssertEqual(
                reason,
                "Request did not redirect to its redirect_uri: answered HTTP 200 after redirecting to 'http://127.0.0.1:\(server.port)/login'"
            )
        }
    }

    private func authorize(redirectUri: String? = nil) async throws -> URL {
        var components = URLComponents(string: "http://127.0.0.1:\(server.port)/oauth/authorize")!
        components.queryItems = redirectUri.map { [URLQueryItem(name: "redirect_uri", value: $0)] }
        return try await networkClient.request(components.url!).redirect()
    }
}
