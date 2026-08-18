import Foundation

class NetworkClient {
    private let session: URLSession
    private let redirectHandler = RedirectHandler()
    private let decoder: JSONDecoder
    private let correlationId: String

    init(decoder: JSONDecoder, configuration: URLSessionConfiguration = .default) {
        self.session = URLSession(configuration: configuration, delegate: redirectHandler, delegateQueue: nil)
        self.decoder = decoder
        self.correlationId = UUID().uuidString
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

/// Captures the terminal HTTP response and body of a redirect task synchronously. `URLSessionDataDelegate`
/// callbacks run one at a time on the session's delegate queue, but `didReceive data:` has no async variant,
/// so an actor-isolated store could be read by `didCompleteWithError` before an in-flight append finishes.
/// A lock lets every callback write in place instead.
private final class RedirectResponseCaptureStore: @unchecked Sendable {
    private let lock = NSLock()
    private var captures = [Int: (response: HTTPURLResponse?, data: Data)]()

    func setResponse(_ response: HTTPURLResponse, for taskIdentifier: Int) {
        lock.lock(); defer { lock.unlock() }
        captures[taskIdentifier, default: (nil, Data())].response = response
    }

    func appendData(_ data: Data, for taskIdentifier: Int) {
        lock.lock(); defer { lock.unlock() }
        captures[taskIdentifier, default: (nil, Data())].data.append(data)
    }

    func pullCapture(for taskIdentifier: Int) -> (response: HTTPURLResponse?, data: Data)? {
        lock.lock(); defer { lock.unlock() }
        return captures.removeValue(forKey: taskIdentifier)
    }
}

class RedirectHandler: NSObject, URLSessionDataDelegate {
    /// Thrown when a redirect task completes without ever redirecting to a private scheme, carrying whatever
    /// terminal HTTP response and body were captured so `DataRequest.redirect()` can decode an `ApiError` from it.
    struct RedirectCompletionFailure: Error {
        let response: HTTPURLResponse?
        let data: Data
    }

    private let continuationManager = RedirectContinuationManager()
    private let captureStore = RedirectResponseCaptureStore()

    func registerContinuation(_ continuation: CheckedContinuation<URL, Error>, for taskIdentifier: Int) async {
        await continuationManager.registerContinuation(continuation, for: taskIdentifier)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        guard let url = request.url, let scheme = url.scheme, !scheme.lowercased().starts(with: "http") else {
            return request
        }

        _ = captureStore.pullCapture(for: task.taskIdentifier)
        let continuation = await continuationManager.pullContinuation(for: task.taskIdentifier)
        continuation?.resume(returning: url)
        return nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        if let httpResponse = response as? HTTPURLResponse {
            captureStore.setResponse(httpResponse, for: dataTask.taskIdentifier)
        }
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        captureStore.appendData(data, for: dataTask.taskIdentifier)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let capture = captureStore.pullCapture(for: task.taskIdentifier)
        Task {
            let continuation = await continuationManager.pullContinuation(for: task.taskIdentifier)

            // empty error means request finished with success
            if let error {
                continuation?.resume(throwing: error)
            } else {
                continuation?.resume(throwing: RedirectCompletionFailure(response: capture?.response, data: capture?.data ?? Data()))
            }
        }
    }
}
