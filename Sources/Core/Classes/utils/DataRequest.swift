import Foundation

class DataRequest {
    private let request: URLRequest
    private let session: URLSession
    private let decoder: JSONDecoder
    private let logger = Logger.shared

    init(request: URLRequest, session: URLSession, decoder: JSONDecoder) {
        self.request = request
        self.session = session
        self.decoder = decoder
    }

    private func isSuccess(_ status: Int) -> Bool {
        status >= 200 && status < 300
    }

    private func parseJson<T: Decodable>(json: Data, type: T.Type) throws -> T {
        do {
            let parsed = try decoder.decode(type, from: json)
            logger.log(parsedResponse: parsed)
            return parsed
        } catch {
            logger.log(error: error)
            throw ReachFiveError.TechnicalError(reason: error.localizedDescription)
        }
    }

    private func handleResponseStatus(status: Int, apiError: ApiError) -> ReachFiveError {
        let error: ReachFiveError = if status == 400 {
            .RequestError(apiError: apiError)
        } else if status == 401 {
            .AuthFailure(reason: "Unauthorized", apiError: apiError)
        } else {
            .TechnicalError(
                reason: "Response with \(status) error code",
                apiError: apiError
            )
        }
        logger.log(error: error)
        return error
    }

    private func processHttpResponse<T>(data: Data, response: URLResponse, onSuccess: (Data) throws -> T) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            let error = ReachFiveError.TechnicalError(reason: "Request without response")
            logger.log(error: error)
            throw error
        }

        logger.log(response: httpResponse, data: data)

        let status = httpResponse.statusCode
        guard isSuccess(status) else {
            let apiError = try parseJson(json: data, type: ApiError.self)
            throw handleResponseStatus(status: status, apiError: apiError)
        }

        return try onSuccess(data)
    }

    func responseJson() async throws {
        logger.log(request: request)
        let (data, response) = try await session.data(for: request)
        try processHttpResponse(data: data, response: response) { _ in }
    }

    func responseJson<T: Decodable>(type: T.Type) async throws -> T {
        logger.log(request: request)
        let (data, response) = try await session.data(for: request)
        return try processHttpResponse(data: data, response: response) { data in
            try parseJson(json: data, type: T.self)
        }
    }

    func redirect() async throws -> URL {
        logger.log(request: request)

        // `URLSession.data(for:delegate:)` would give us a per-call delegate for free, but it needs iOS 15;
        // a throwaway session (inheriting the shared session's configuration, so test stubs still apply)
        // gets the same effect — exclusive to this one task, no shared state to correlate by task identifier.
        let delegate = PrivateSchemeRedirectDelegate()
        let redirectSession = URLSession(configuration: session.configuration, delegate: delegate, delegateQueue: nil)
        defer { redirectSession.finishTasksAndInvalidate() }

        return try await withCheckedThrowingContinuation { continuation in
            let task = redirectSession.dataTask(with: request) { data, response, error in
                if let redirectedTo = delegate.redirectedTo {
                    continuation.resume(returning: redirectedTo)
                    return
                }

                if let error {
                    // The redirection was followed instead of being handed to our delegate: the callback is
                    // still there, in the URL `URLSession` then failed to load. Recover it rather than losing
                    // a login over it.
                    if let callback = Self.privateSchemeCallback(from: error) {
                        continuation.resume(returning: callback)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                guard let response else {
                    continuation.resume(throwing: Self.redirectionNotSeen())
                    return
                }

                continuation.resume(with: Result {
                    try self.processHttpResponse(data: data ?? Data(), response: response) { _ in
                        let status = (response as? HTTPURLResponse)?.statusCode
                        let error = ReachFiveError.TechnicalError(reason: "Request did not redirect as expected: answered \(status.map(String.init) ?? "no") HTTP status instead of a redirection to the private scheme")
                        self.logger.log(error: error)
                        throw error
                    }
                })
            }
            task.resume()
        }
    }

    /// The callback URL of a redirection that was followed instead of intercepted.
    ///
    /// `URLSession` has no handler for a private scheme, so following such a redirection can only end in
    /// `unsupportedURL` — but the URL it failed to load is the callback itself, authorization code included.
    /// A request the SDK sends is always `https`, so a private scheme here can only come from a redirection.
    ///
    /// This is what a network interception layer (SSL pinning, an APM agent, a `URLProtocol`) causes when it
    /// substitutes itself for the session delegate and answers the redirection on its own instead of
    /// forwarding it. Recovering costs nothing in security: the TLS connection this callback comes from was
    /// already made and validated, and the callback URL itself is never loaded.
    private static func privateSchemeCallback(from error: Error) -> URL? {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain, error.code == NSURLErrorUnsupportedURL else { return nil }

        let failing = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL
            ?? (error.userInfo[NSURLErrorFailingURLStringErrorKey] as? String).flatMap(URL.init(string:))
        guard let failing, let scheme = failing.scheme, !scheme.lowercased().starts(with: "http") else {
            return nil
        }

        return failing
    }

    /// The task ended with no redirection, no response and no error — `URLSession` keeps nothing of a
    /// redirection a delegate refuses, not even `task.response`, so this is all there is to report.
    private static func redirectionNotSeen() -> ReachFiveError {
        let error = ReachFiveError.TechnicalError(reason: """
        Request did not redirect as expected: the redirection was refused before the SDK could read it. \
        A network interception layer that handles redirects on the SDK's URLSession (SSL pinning, an APM \
        agent, a URLProtocol) is the usual cause; it must forward willPerformHTTPRedirection to the SDK's \
        own delegate, which returns nil for a private scheme.
        """)
        Logger.shared.log(error: error)
        return error
    }
}

/// Follows redirects as `URLSession` normally would, except a redirect to a private (non-http) scheme —
/// the target of an `/oauth/authorize` callback — which it captures instead of following, since `URLSession`
/// has no handler for it. Scoped to a single `redirect()` call (its own throwaway session), so a plain
/// stored property is enough: no shared state, no locking.
private final class PrivateSchemeRedirectDelegate: NSObject, URLSessionTaskDelegate {
    private(set) var redirectedTo: URL?

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        guard let url = request.url, let scheme = url.scheme, !scheme.lowercased().starts(with: "http") else {
            return request
        }

        redirectedTo = url
        return nil
    }
}
