import Foundation

/// A minimal `URLProtocol` stub used to script HTTP responses — including a redirect to a private
/// scheme — without touching the network, so `NetworkClient`/`DataRequest` can be exercised end to end.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
        let networkError: Error?

        static func response(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) -> Stub {
            Stub(statusCode: statusCode, headers: headers, body: body, networkError: nil)
        }

        static func redirect(to location: String, statusCode: Int = 302) -> Stub {
            Stub(statusCode: statusCode, headers: ["Location": location], body: Data(), networkError: nil)
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

        if let networkError = stub.networkError {
            client?.urlProtocol(self, didFailWithError: networkError)
            return
        }

        if let location = stub.headers["Location"], let redirectURL = URL(string: location) {
            let redirectResponse = HTTPURLResponse(url: request.url!, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
            var redirectRequest = URLRequest(url: redirectURL)
            redirectRequest.httpMethod = request.httpMethod
            client?.urlProtocol(self, wasRedirectedTo: redirectRequest, redirectResponse: redirectResponse)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
