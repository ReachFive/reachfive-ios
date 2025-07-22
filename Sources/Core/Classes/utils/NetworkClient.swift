import Foundation

class NetworkClient {
    private let session: URLSession
    private let redirectHandler = RedirectHandler()
    private let decoder: JSONDecoder

    init(decoder: JSONDecoder) {
        self.session = URLSession(configuration: .default, delegate: redirectHandler, delegateQueue: nil)
        self.decoder = decoder
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    func request(_ url: URL, method: HttpMethod = .get, headers: [String: String]? = nil, body: Data? = nil) -> DataRequest {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue
        urlRequest.allHTTPHeaderFields = headers
        urlRequest.httpBody = body
        if body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return DataRequest(request: urlRequest, session: session, redirectHandler: redirectHandler, decoder: decoder)
    }

    func request(_ url: URL, method: HttpMethod = .get, headers: [String: String]? = nil, parameters: [String: Any]?) -> DataRequest {
        let body = parameters.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        return request(url, method: method, headers: headers, body: body)
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
        if let url = request.url, let scheme = url.scheme, !scheme.lowercased().starts(with: "http") {
            let continuation = await continuationManager.pullContinuation(for: task.taskIdentifier)
            continuation?.resume(returning: url)
            return nil
        }

        return request
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task {
            let continuation = await continuationManager.pullContinuation(for: task.taskIdentifier)

            if let error {
                continuation?.resume(throwing: error)
            } else if let continuation {
                continuation.resume(throwing: ReachFiveError.TechnicalError(reason: "Request did not redirect as expected"))
            }
        }
    }
}
