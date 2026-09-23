import Foundation

/// A minimal `URLProtocol` stub used to script the outcomes a task can end on, without touching the network,
/// so `NetworkClient`/`DataRequest` can be exercised end to end.
///
/// It scripts what `URLSession` hands back, never how it gets there: a redirection is delivered as the
/// response that ends the task, which is what a refused redirection leaves behind. `RedirectRefusalTests`
/// pins that against a real exchange.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
        let networkError: Error?
        var finishWithoutResponse = false

        static func response(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) -> Stub {
            Stub(statusCode: statusCode, headers: headers, body: body, networkError: nil)
        }

        /// Ends the load with neither a response nor an error, which only an interception layer can produce.
        static let finishWithoutResponse = Stub(statusCode: 0, headers: [:], body: Data(), networkError: nil, finishWithoutResponse: true)

        static func redirection(to location: String, statusCode: Int = 302) -> Stub {
            .response(statusCode: statusCode, headers: ["Location": location])
        }

        static func networkFailure(_ error: Error) -> Stub {
            Stub(statusCode: 0, headers: [:], body: Data(), networkError: error)
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
