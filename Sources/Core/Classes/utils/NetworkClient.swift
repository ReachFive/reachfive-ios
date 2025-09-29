import Foundation

class NetworkClient {
    private let session: URLSession
    private let redirectHandler = RedirectHandler()
    private let decoder: JSONDecoder
    private let storage: Storage
    static let correlationIdKey = "CORRELATION_ID"

    init(decoder: JSONDecoder, storage: Storage) {
        self.session = URLSession(configuration: .default, delegate: redirectHandler, delegateQueue: nil)
        self.decoder = decoder
        self.storage = storage
    }

    deinit {
        session.finishTasksAndInvalidate()
    }
    
    private func retrieveCorrelationId() -> String {
        guard let correlationId: String = storage.get(key: NetworkClient.correlationIdKey) else {
            let generated = UUID().uuidString
            self.storage.save(key: NetworkClient.correlationIdKey, value: generated)
            return generated
        }
        return correlationId
    }
    
    func request(_ url: URL, method: HttpMethod = .get, headers: [String: String]? = nil, body: Data? = nil) -> DataRequest {
        var urlRequest = URLRequest(url: url)
        
        urlRequest.httpMethod = method.rawValue
        let computedHeaders: [String : String] = headers ?? [:]
        let withCorrelationHeaders: [String : String] = computedHeaders.merging(["X-R5-Correlation-Id": retrieveCorrelationId()], uniquingKeysWith: { (_, new) in new})

        urlRequest.allHTTPHeaderFields = withCorrelationHeaders
        urlRequest.httpBody = body
        if body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return DataRequest(request: urlRequest, session: session, redirectHandler: redirectHandler, decoder: decoder)
    }

    func request(_ url: URL, method: HttpMethod = .get, headers: [String: String]? = nil, parameters: [String: Any]?) -> DataRequest {
        let body = parameters.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        let computedHeaders: [String : String] = headers ?? [:]
        let withCorrelationHeaders: [String : String] = computedHeaders.merging(["X-Correlation-Id": retrieveCorrelationId()], uniquingKeysWith: { (_, new) in new})
        return request(url, method: method, headers:  withCorrelationHeaders, body: body)
    }
}

private actor RedirectContinuationManager {
    var redirectContinuations = [Int: CheckedContinuation<URL, Error>]()

    func registerContinuation(_ continuation: CheckedContinuation<URL, Error>, for taskIdentifier: Int) {
        redirectContinuations[taskIdentifier] = continuation
    }

    func pullContinuation(for taskIdentifier: Int) -> CheckedContinuation<URL, Error>? {
        redirectContinuations.removeValue(forKey: taskIdentifier)
    }
}

class RedirectHandler: NSObject, URLSessionTaskDelegate {
    private let continuationManager = RedirectContinuationManager()

    func registerContinuation(_ continuation: CheckedContinuation<URL, Error>, for taskIdentifier: Int) async {
        await continuationManager.registerContinuation(continuation, for: taskIdentifier)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        guard let url = request.url, let scheme = url.scheme, !scheme.lowercased().starts(with: "http") else {
            return request
        }
        
        let continuation = await continuationManager.pullContinuation(for: task.taskIdentifier)
        continuation?.resume(returning: url)
        return nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task {
            let continuation = await continuationManager.pullContinuation(for: task.taskIdentifier)

            // empty error means request finished with success
            if let error {
                continuation?.resume(throwing: error)
            } else {
                continuation?.resume(throwing: ReachFiveError.TechnicalError(reason: "Request did not redirect as expected"))
            }
        }
    }
}
