import Foundation

/// A minimal `URLProtocol` stub used to script the outcomes a task can end on, without touching the network,
/// so `NetworkClient`/`DataRequest` can be exercised end to end.
///
/// It scripts what `URLSession` hands back, never how it gets there: a redirection is delivered as the
/// response that ends the task, which is what both a refusal by the SDK's own delegate and one by an
/// interception layer leave behind. `RedirectRefusalTests` is what pins that against a real exchange —
/// signalling `wasRedirectedTo` from here would not, since the URL loading system keeps no response of its
/// own in that case.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
        let networkError: Error?
        let finishWithoutResponse: Bool

        static func response(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) -> Stub {
            Stub(statusCode: statusCode, headers: headers, body: body, networkError: nil, finishWithoutResponse: false)
        }

        /// The redirect response as the task's own, the way a refused redirection ends it: the `Location`
        /// header is there, and no redirection was ever followed.
        static func redirection(to location: String, statusCode: Int = 302) -> Stub {
            .response(statusCode: statusCode, headers: ["Location": location])
        }

        static func networkFailure(_ error: Error) -> Stub {
            Stub(statusCode: 0, headers: [:], body: Data(), networkError: error, finishWithoutResponse: false)
        }

        /// Ends the load without ever delivering a response — no response, no error — which is what an
        /// interception layer standing in for `URLSession` can leave behind.
        static func finishWithoutResponse() -> Stub {
            Stub(statusCode: 0, headers: [:], body: Data(), networkError: nil, finishWithoutResponse: true)
        }
    }

    static var stubHandler: ((URLRequest) -> Stub)?

    static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let stub = Self.stubHandler?(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        if stub.finishWithoutResponse {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if let networkError = stub.networkError {
            client?.urlProtocol(self, didFailWithError: networkError)
            return
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
