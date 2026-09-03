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
/// `/oauth/authorize` callback — which it refuses, since `URLSession` has no handler for such a scheme.
///
/// Refusing leaves the callback in the `Location` header of the response that then ends the task, which is
/// where ``DataRequest/redirect()`` reads it. Nothing has to be carried out of this delegate, so it holds no
/// state and one instance answers every task of the session.
class CustomSchemeRedirectRefusal: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        request.url?.hasCustomScheme == true ? nil : request
    }
}
