import XCTest
@testable import Reach5

/// What `DataRequest.redirect()` rests on, measured against a real HTTP exchange rather than a stub: refusing
/// a redirection ends the task on the redirect response itself, `Location` header included.
///
/// Not a documented contract, which is why it is pinned here: it is the mechanism this SDK shipped throughout
/// 8.x, and the whole reading of the `/oauth/authorize` callback depends on it. A runtime that stopped
/// keeping that response would fail these two tests rather than silently break every login.
final class RedirectRefusalTests: XCTestCase {
    private var server: LoopbackHTTPServer!

    override func tearDown() {
        server?.stop()
        server = nil
        super.tearDown()
    }

    /// A redirection to the app's custom scheme: the delegate refuses it, and the callback is still readable.
    func testRefusedRedirectionLeavesTheCallbackInTheLocationHeader() async throws {
        server = try LoopbackHTTPServer { _ in
            "HTTP/1.1 302 Found\r\nLocation: reachfive-client://callback?code=abc123\r\nContent-Length: 0\r\n\r\n"
        }

        let (_, response) = try await session().data(for: URLRequest(url: authorizeURL()))

        let redirection = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(redirection.statusCode, 302)
        XCTAssertEqual(redirection.value(forHTTPHeaderField: "Location"), "reachfive-client://callback?code=abc123")
    }

    /// A redirection to a web scheme is none of the SDK's business: the delegate lets `URLSession` follow it,
    /// so what comes back is the target's response, not the redirection.
    func testWebRedirectionIsStillFollowed() async throws {
        server = try LoopbackHTTPServer { requestLine in
            requestLine.contains("/oauth/authorize")
                ? "HTTP/1.1 302 Found\r\nLocation: /elsewhere\r\nContent-Length: 0\r\n\r\n"
                : "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}"
        }

        let (_, response) = try await session().data(for: URLRequest(url: authorizeURL()))

        let followed = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(followed.statusCode, 200)
        XCTAssertEqual(followed.url?.path, "/elsewhere")
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        // Well under URLSession's 60 s default: a server that stops answering must fail the test, not stall
        // the whole suite on it.
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration, delegate: CustomSchemeRedirectRefusal(), delegateQueue: nil)
    }

    private func authorizeURL() -> URL {
        URL(string: "http://127.0.0.1:\(server.port)/oauth/authorize")!
    }
}
