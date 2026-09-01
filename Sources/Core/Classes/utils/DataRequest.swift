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

    /// Runs the request, the way `URLSession.data(for:)` would — except on the one outcome it cannot
    /// represent: a task ending with neither a response nor an error.
    ///
    /// `data(for:)` resolves here to the form Foundation back-deploys over `dataTask(with:completionHandler:)`,
    /// since the iOS 15 `data(for:delegate:)` is out of reach of this SDK's iOS 13 floor — and that form
    /// force-unwraps the response, so it traps (measured: `SIGTRAP`, inside Foundation) on that outcome. The
    /// completion handler reports it plainly, and it is precisely what a network interception layer standing
    /// in for `URLSession` produces, so the SDK says so rather than taking the app down.
    private func perform() async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let response {
                    continuation.resume(returning: (data ?? Data(), response))
                } else {
                    continuation.resume(throwing: Self.noResponseAtAll())
                }
            }.resume()
        }
    }

    func responseJson() async throws {
        logger.log(request: request)
        let (data, response) = try await perform()
        try processHttpResponse(data: data, response: response) { _, _ in }
    }

    func responseJson<T: Decodable>(type: T.Type) async throws -> T {
        logger.log(request: request)
        let (data, response) = try await perform()
        return try processHttpResponse(data: data, response: response) { data, _ in
            try parseJson(json: data, type: T.self)
        }
    }

    /// The `/oauth/authorize` call, whose result is not a response to read but a redirection to the app's
    /// custom scheme: the callback URL, with the authorization code in it.
    ///
    /// That redirection is refused rather than followed by ``CustomSchemeRedirectRefusal``, the session's
    /// delegate — `URLSession` has no handler for such a scheme — and refusing ends the task on the redirect
    /// response itself, `Location` header included. Reading the callback from that header, rather than from
    /// the `newRequest` the delegate is handed, is what makes the call survive a network interception layer
    /// (SSL pinning, an APM agent, a `URLProtocol`) answering `willPerformHTTPRedirection` in the SDK's
    /// place: refusing is what the SDK wanted anyway, so whoever answers, the callback ends up in the same
    /// header. Hence an ordinary ``perform()``, exactly like every other call above.
    func redirect() async throws -> URL {
        logger.log(request: request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await perform()
        } catch {
            guard let callback = Self.callbackURL(ofRedirectionFollowedIn: error) else { throw error }
            // Without this line the recovery is silent, and an interception layer breaking the SDK's redirect
            // handling stays invisible for as long as the recovery holds. The callback URL is left out of it:
            // it carries the authorization code.
            logger.log("""
            The redirection to the app's custom scheme was followed instead of being refused; the callback \
            was recovered from the unsupportedURL error it failed on. A network interception layer answering \
            willPerformHTTPRedirection on the SDK's URLSession is the usual cause.
            """)
            return callback
        }

        if let redirection = response as? HTTPURLResponse, (300 ..< 400).contains(redirection.statusCode) {
            // The only response this call ever gets when it works, and the one nothing used to log — which is
            // what made an `/oauth/authorize` failure take days to diagnose. `Logger` prints the status and
            // the request URL, never the headers, so the authorization code stays out of it.
            logger.log(response: redirection, data: data)
            guard let callback = Self.callbackURL(of: redirection) else {
                throw Self.unusableRedirection(redirection)
            }
            return callback
        }

        return try processHttpResponse(data: data, response: response) { _, httpResponse in
            let error = ReachFiveError.TechnicalError(reason: "Request did not redirect as expected: answered \(httpResponse.statusCode) HTTP status instead of a redirection to the app's custom scheme")
            self.logger.log(error: error)
            throw error
        }
    }

    /// The callback URL a refused redirection carries in its `Location` header, `nil` when it leads elsewhere
    /// than the app's custom scheme or carries no `Location` at all.
    ///
    /// Refusing a redirection makes `URLSession` end the task on the redirect response itself, `Location`
    /// included. That is not a documented contract, but it is the mechanism this SDK shipped throughout 8.x
    /// (Alamofire's `Redirector.doNotFollow`, then this very header read), and `RedirectRefusalTests` pins it
    /// against a real HTTP exchange — a `URLProtocol` stub cannot reproduce it.
    private static func callbackURL(of redirection: HTTPURLResponse) -> URL? {
        guard let location = redirection.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location), url.hasCustomScheme
        else {
            return nil
        }

        return url
    }

    /// The callback URL of a redirection that was followed instead of being refused.
    ///
    /// `URLSession` has no handler for the app's custom scheme, so following such a redirection ends in
    /// `unsupportedURL` — and the URL it failed to load is the callback itself, authorization code included.
    /// A request the SDK sends is always `https`, so a non-web scheme here can only come from a redirection.
    ///
    /// The cause is an interception layer that forwards the redirection to `URLSession` rather than refusing
    /// it. Recovering costs nothing in security: the TLS connection this callback comes from was already made
    /// and validated, and the callback URL itself is never loaded.
    ///
    /// The shape of that error — `NSURLErrorDomain`, `unsupportedURL`, the failing URL under one of the two
    /// `userInfo` keys — is measured on an iOS 26 simulator and on Mac Catalyst, not a documented contract.
    /// A runtime reporting it otherwise gets `nil` here and the raw error, which is the behaviour that
    /// preceded this recovery.
    private static func callbackURL(ofRedirectionFollowedIn error: Error) -> URL? {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain, error.code == NSURLErrorUnsupportedURL else { return nil }

        let failing = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL
            ?? (error.userInfo[NSURLErrorFailingURLStringErrorKey] as? String).flatMap(URL.init(string:))
        guard let failing, failing.hasCustomScheme else { return nil }

        return failing
    }

    /// The task ended with no response and no error at all — nothing an HTTP exchange produces, so the only
    /// plausible source is something answering for `URLSession` on this session.
    private static func noResponseAtAll() -> ReachFiveError {
        let error = ReachFiveError.TechnicalError(reason: """
        Request ended without a response nor an error. A network interception layer standing in for \
        URLSession on the SDK's session (SSL pinning, an APM agent, a URLProtocol) is the usual cause.
        """)
        Logger.shared.log(error: error)
        return error
    }

    /// A redirection that ended the task but leads elsewhere than the app's custom scheme — an interception
    /// layer rewriting the target to a block page, or a redirection stripped of its `Location`. Names where it
    /// leads, which the decoding of a body that isn't an `ApiError` never would.
    private static func unusableRedirection(_ redirection: HTTPURLResponse) -> ReachFiveError {
        let location = redirection.value(forHTTPHeaderField: "Location")
        let error = ReachFiveError.TechnicalError(reason: "Request did not redirect as expected: answered a \(redirection.statusCode) redirection to \(location.map { "'\($0)'" } ?? "nowhere — no Location header"), not to the app's custom scheme")
        Logger.shared.log(error: error)
        return error
    }
}

