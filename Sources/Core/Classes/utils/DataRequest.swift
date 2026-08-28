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

    private func processHttpResponse<T>(data: Data, response: URLResponse, onSuccess: (Data, HTTPURLResponse) throws -> T) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            let error = ReachFiveError.TechnicalError(reason: "Request without response")
            logger.log(error: error)
            throw error
        }

        logger.log(response: httpResponse, data: data)

        let status = httpResponse.statusCode
        guard isSuccess(status) else {
            // A body that is not an `ApiError` — an HTML error page from a proxy, an empty 502 — otherwise
            // surfaces as a JSON decoding message alone, with the status code nowhere in it. `parseJson`
            // has already logged that decoding failure by the time this falls back on the status.
            guard let apiError = try? parseJson(json: data, type: ApiError.self) else {
                let error = ReachFiveError.TechnicalError(reason: "Response with \(status) error code")
                logger.log(error: error)
                throw error
            }
            throw handleResponseStatus(status: status, apiError: apiError)
        }

        return try onSuccess(data, httpResponse)
    }

    func responseJson() async throws {
        logger.log(request: request)
        let (data, response) = try await session.data(for: request)
        try processHttpResponse(data: data, response: response) { _, _ in }
    }

    func responseJson<T: Decodable>(type: T.Type) async throws -> T {
        logger.log(request: request)
        let (data, response) = try await session.data(for: request)
        return try processHttpResponse(data: data, response: response) { data, _ in
            try parseJson(json: data, type: T.self)
        }
    }

    func redirect() async throws -> URL {
        logger.log(request: request)

        // `URLSession.data(for:delegate:)` would give us a per-call delegate for free, but it needs iOS 15;
        // a throwaway session (inheriting the shared session's configuration, so test stubs still apply)
        // gets the same effect — exclusive to this one task, no shared state to correlate by task identifier.
        // It comes with its own connection pool, so this one call pays a TLS handshake it could otherwise
        // have reused: the price of the isolation, on a call that happens once per login.
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
                        // Without this line the recovery is silent, and an interception layer breaking the
                        // SDK's redirect handling stays invisible for as long as the recovery holds. The
                        // callback URL is left out of it: it carries the authorization code.
                        self.logger.log("""
                        The redirection to the private scheme was followed instead of being handed to the \
                        SDK's session delegate; the callback was recovered from the unsupportedURL error it \
                        failed on. A network interception layer answering willPerformHTTPRedirection on the \
                        SDK's URLSession is the usual cause.
                        """)
                        continuation.resume(returning: callback)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                // Another delegate refused the redirection before ours could intercept it. `URLSession` then
                // hands the redirect response over as the task's own, `Location` header included — the
                // callback is right there.
                if let callback = Self.privateSchemeCallback(fromRedirectionRefusedIn: response) {
                    // Silent otherwise, same as above.
                    self.logger.log("""
                    The redirection to the private scheme was refused before the SDK's session delegate could \
                    intercept it; the callback was recovered from the Location header of the redirect \
                    response. A network interception layer answering willPerformHTTPRedirection on the SDK's \
                    URLSession is the usual cause.
                    """)
                    continuation.resume(returning: callback)
                    return
                }

                guard let response else {
                    continuation.resume(throwing: Self.noResponseAtAll())
                    return
                }

                // A redirection the recovery just turned down: it leads somewhere else than the private
                // scheme. `processHttpResponse` would only report a body it cannot decode, so say where.
                if let unusable = Self.unusableRedirection(response) {
                    continuation.resume(throwing: unusable)
                    return
                }

                continuation.resume(with: Result {
                    try self.processHttpResponse(data: data ?? Data(), response: response) { _, httpResponse in
                        let error = ReachFiveError.TechnicalError(reason: "Request did not redirect as expected: answered \(httpResponse.statusCode) HTTP status instead of a redirection to the private scheme")
                        self.logger.log(error: error)
                        throw error
                    }
                })
            }
            task.resume()
        }
    }

    /// The callback URL of a redirection another delegate refused before ours could intercept it.
    ///
    /// Refusing a redirection makes `URLSession` end the task on the redirect response itself, `Location`
    /// header included — which is where the callback is. This is what a network interception layer (SSL
    /// pinning, an APM agent, a `URLProtocol`) causes when it answers `willPerformHTTPRedirection` on its own
    /// instead of forwarding it to the session's real delegate; refusing to follow a private scheme is what
    /// the SDK wanted anyway, so honouring that answer costs nothing.
    ///
    /// That `URLSession` keeps the redirect response rather than dropping it is measured, on an iOS 26
    /// simulator and on Mac Catalyst, not a documented contract — an older runtime keeping nothing would
    /// fall through to `noResponseAtAll()` below, which is the pre-existing behaviour rather than a new one.
    private static func privateSchemeCallback(fromRedirectionRefusedIn response: URLResponse?) -> URL? {
        guard let response = response as? HTTPURLResponse, (300 ..< 400).contains(response.statusCode),
              let location = response.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location), url.hasPrivateScheme else
        {
            return nil
        }

        return url
    }

    /// The callback URL of a redirection that was followed instead of intercepted.
    ///
    /// `URLSession` has no handler for a private scheme, so following such a redirection ends in
    /// `unsupportedURL` — and the URL it failed to load is the callback itself, authorization code included.
    /// A request the SDK sends is always `https`, so a private scheme here can only come from a redirection.
    ///
    /// Same cause as above, other outcome: an interception layer that forwards the redirection to
    /// `URLSession` rather than refusing it. Recovering costs nothing in security either — the TLS connection
    /// this callback comes from was already made and validated, and the callback URL itself is never loaded.
    ///
    /// The shape of that error — `NSURLErrorDomain`, `unsupportedURL`, the failing URL under one of the two
    /// `userInfo` keys — is measured on an iOS 26 simulator and on Mac Catalyst, not a documented contract.
    /// A runtime reporting it otherwise gets `nil` here and the raw error, which is the behaviour that
    /// preceded this recovery.
    private static func privateSchemeCallback(from error: Error) -> URL? {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain, error.code == NSURLErrorUnsupportedURL else { return nil }

        let failing = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL
            ?? (error.userInfo[NSURLErrorFailingURLStringErrorKey] as? String).flatMap(URL.init(string:))
        guard let failing, failing.hasPrivateScheme else { return nil }

        return failing
    }

    /// A redirection that ended the task but leads elsewhere than the private scheme — an interception layer
    /// rewriting the target to a block page, or a redirection stripped of its `Location`. Names where it
    /// leads, which the decoding of a body that isn't an `ApiError` never would.
    private static func unusableRedirection(_ response: URLResponse) -> ReachFiveError? {
        guard let response = response as? HTTPURLResponse, (300 ..< 400).contains(response.statusCode) else {
            return nil
        }

        let location = response.value(forHTTPHeaderField: "Location")
        let error = ReachFiveError.TechnicalError(reason: "Request did not redirect as expected: answered a \(response.statusCode) redirection to \(location.map { "'\($0)'" } ?? "nowhere — no Location header"), not to the private scheme the SDK intercepts")
        Logger.shared.log(error: error)
        return error
    }

    /// The task ended with no redirection, no response and no error at all — nothing an HTTP exchange
    /// produces, so the only plausible source is something answering for `URLSession` on this session.
    private static func noResponseAtAll() -> ReachFiveError {
        let error = ReachFiveError.TechnicalError(reason: """
        Request did not redirect as expected, and ended without a response nor an error. A network \
        interception layer standing in for URLSession on the SDK's session (SSL pinning, an APM agent, a \
        URLProtocol) is the usual cause.
        """)
        Logger.shared.log(error: error)
        return error
    }
}

/// Follows redirects as `URLSession` normally would, except a redirect to a private (non-http) scheme —
/// the target of an `/oauth/authorize` callback — which it captures instead of following, since `URLSession`
/// has no handler for it. Scoped to a single `redirect()` call (its own throwaway session), so there is no
/// task identifier to correlate anything by.
///
/// The capture still crosses threads, hence the lock: the async form of the delegate method does not run on
/// the session's delegate queue (measured: a cooperative thread, with `OperationQueue.current` nil), whereas
/// the task's completion handler, which reads the capture, does.
private final class PrivateSchemeRedirectDelegate: NSObject, URLSessionTaskDelegate {
    private let lock = NSLock()
    private var captured: URL?

    var redirectedTo: URL? {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        guard let url = request.url, url.hasPrivateScheme else {
            return request
        }

        lock.lock()
        captured = url
        lock.unlock()
        return nil
    }
}
