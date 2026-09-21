import Foundation

class NetworkClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let correlationId: String

    init(decoder: JSONDecoder, configuration: URLSessionConfiguration = .default) {
        session = URLSession(configuration: configuration, delegate: CustomSchemeRedirectRefusal(), delegateQueue: nil)
        self.decoder = decoder
        correlationId = UUID().uuidString
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    func request(_ url: URL, method: HttpMethod = .get, headers: [String: String]? = nil, body: Data? = nil) -> DataRequest {
        var urlRequest = URLRequest(url: url)

        urlRequest.httpMethod = method.rawValue

        var headersWithCorrelation = headers ?? [:]
        headersWithCorrelation["X-R5-Correlation-Id"] = correlationId
        urlRequest.allHTTPHeaderFields = headersWithCorrelation
        urlRequest.httpBody = body

        if body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return DataRequest(request: urlRequest, session: session, decoder: decoder)
    }

    func request(_ url: URL, method: HttpMethod = .get, headers: [String: String]? = nil, parameters: [String: Any]?) -> DataRequest {
        let body = parameters.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        return request(url, method: method, headers: headers, body: body)
    }
}

/// Follows redirections as `URLSession` normally would, except one to the app's custom scheme — the
/// `/oauth/authorize` callback — which it refuses. The task then ends on the redirect response itself, and
/// ``DataRequest/redirect()`` reads the callback from its `Location` header.
class CustomSchemeRedirectRefusal: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        request.url?.hasCustomScheme == true ? nil : request
    }
}
