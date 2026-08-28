import Foundation

class NetworkClient {
    private let session: URLSession
    private let redirectHandler: RedirectHandler
    private let decoder: JSONDecoder
    private let correlationId: String

    init(decoder: JSONDecoder, configuration: URLSessionConfiguration = .default, authenticationChallengeHandler: AuthenticationChallengeHandler? = nil) {
        redirectHandler = RedirectHandler(authenticationChallengeHandler)
        session = URLSession(configuration: configuration, delegate: redirectHandler, delegateQueue: nil)
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

        return DataRequest(request: urlRequest, session: session, redirectHandler: redirectHandler, decoder: decoder)
    }

    func request(_ url: URL, method: HttpMethod = .get, headers: [String: String]? = nil, parameters: [String: Any]?) -> DataRequest {
        let body = parameters.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        return request(url, method: method, headers: headers, body: body)
    }
}

/// Forwards an authentication challenge to the ``AuthenticationChallengeHandler`` an app configured, if any.
/// Deliberately the only thing the SDK lets an app take over on its session: a delegate that could also
/// answer `willPerformHTTPRedirection` would take the `/oauth/authorize` callback away from the SDK.
///
/// Kept apart from ``RedirectHandler`` below, which inherits it, so that what an app is allowed to answer
/// stays visibly separate from what the SDK answers for itself.
class ChallengeForwardingDelegate: NSObject, URLSessionDelegate {
    private let authenticationChallengeHandler: AuthenticationChallengeHandler?

    init(_ authenticationChallengeHandler: AuthenticationChallengeHandler?) {
        self.authenticationChallengeHandler = authenticationChallengeHandler
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let authenticationChallengeHandler else { return (.performDefaultHandling, nil) }
        return await authenticationChallengeHandler(challenge)
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

class RedirectHandler: ChallengeForwardingDelegate, URLSessionTaskDelegate {
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
