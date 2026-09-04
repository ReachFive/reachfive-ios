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

    private func isRedirection(_ status: Int) -> Bool {
        status >= 300 && status < 400
    }

    /// Logs an error and hands it back, so a throw site stays one expression.
    private func logged(_ error: ReachFiveError) -> ReachFiveError {
        logger.log(error: error)
        return error
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
            .TechnicalError(reason: "Response with \(status) error code", apiError: apiError)
        }
        return logged(error)
    }

    /// Checks the response is one the caller can read, and hands it back cast. Throws on anything else, the
    /// `ApiError` of the body decoded into the error whenever the body carries one.
    ///
    /// A `nil` response reaches here only from ``perform()``, on a task that ended with neither a response
    /// nor an error — which is what a network interception layer standing in for `URLSession` can produce.
    @discardableResult
    private func validate(data: Data, response: URLResponse?) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw logged(.TechnicalError(reason: "Request ended without a response nor an error"))
        }

        logger.log(response: httpResponse, data: data)

        let status = httpResponse.statusCode
        guard isSuccess(status) else {
            // A body that is not an `ApiError` — an HTML error page from a proxy, an empty 502 — otherwise
            // surfaces as a JSON decoding message alone, with the status code nowhere in it. `parseJson`
            // has already logged that decoding failure by the time this falls back on the status.
            guard let apiError = try? parseJson(json: data, type: ApiError.self) else {
                throw logged(.TechnicalError(reason: "Response with \(status) error code"))
            }
            throw handleResponseStatus(status: status, apiError: apiError)
        }

        return httpResponse
    }

    /// Runs the request the way `URLSession.data(for:)` does, cancellation included — except on the one
    /// outcome it cannot represent: a task ending with neither a response nor an error, which its
    /// back-deployed form force-unwraps and traps on (measured: `SIGTRAP`, inside Foundation). Handing that
    /// back as a `nil` response lets ``validate(data:response:)`` name it instead.
    private func perform() async throws -> (Data, URLResponse?) {
        let running = RunningTask()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                running.start(session.dataTask(with: request) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (data ?? Data(), response))
                    }
                })
            }
        } onCancel: {
            running.cancel()
        }
    }

    func responseJson() async throws {
        logger.log(request: request)
        let (data, response) = try await perform()
        try validate(data: data, response: response)
    }

    func responseJson<T: Decodable>(type: T.Type) async throws -> T {
        logger.log(request: request)
        let (data, response) = try await perform()
        try validate(data: data, response: response)
        return try parseJson(json: data, type: T.self)
    }

    /// The `/oauth/authorize` call, whose result is not a response to read but a redirection to the app's
    /// custom scheme: the callback URL, with the authorization code in it.
    ///
    /// ``CustomSchemeRedirectRefusal`` refuses that redirection, which ends the task on the redirect response
    /// itself, `Location` header included. Reading the callback from that header rather than from the
    /// `newRequest` handed to the delegate is what makes the call survive a network interception layer
    /// answering `willPerformHTTPRedirection` in the SDK's place: refusing is what the SDK wanted anyway, so
    /// whoever refuses leaves the callback in the same header.
    func redirect() async throws -> URL {
        logger.log(request: request)

        let data: Data
        let response: URLResponse?
        do {
            (data, response) = try await perform()
        } catch {
            guard let callback = Self.callbackFollowedInstead(of: error) else { throw error }
            // Without this line the recovery is silent, and an interception layer breaking the SDK's redirect
            // handling stays invisible for as long as the recovery holds. The callback URL is left out of it:
            // it carries the authorization code.
            logger.log("The redirection to the app's custom scheme was followed instead of being refused; the callback was recovered from the unsupportedURL error it failed on.")
            return callback
        }

        if let redirection = response as? HTTPURLResponse, isRedirection(redirection.statusCode) {
            // The only response this call ever gets when it works, and the one nothing used to log — which is
            // what made an `/oauth/authorize` failure take days to diagnose. `Logger` prints the status and
            // the request URL, never the headers, so the authorization code stays out of it.
            logger.log(response: redirection, data: data)

            let location = redirection.value(forHTTPHeaderField: "Location")
            guard let callback = location.flatMap(URL.init(string:)), callback.hasCustomScheme else {
                throw notRedirected(redirection, location: location)
            }
            return callback
        }

        // Anything but a 2xx has thrown by now, `ApiError` decoded — a rejected `redirect_uri` answers
        // `403 error.client.redirectUrlNotAllowed`. What is left is a final response that simply did not
        // redirect, and its status is all there is to report.
        throw notRedirected(try validate(data: data, response: response), location: nil)
    }

    /// The expected redirection did not happen: either the task ended on an ordinary HTTP response, or on a
    /// redirection leading elsewhere than the app's custom scheme — an interception layer rewriting the target
    /// to a block page, or a redirection stripped of its `Location`. Names where it actually leads, which
    /// decoding a body that is not an `ApiError` never would.
    private func notRedirected(_ response: HTTPURLResponse, location: String?) -> ReachFiveError {
        let target = isRedirection(response.statusCode)
            ? " with \(location.map { "Location '\($0)'" } ?? "no Location header")"
            : ""
        return logged(.TechnicalError(
            reason: "Request did not redirect to the app's custom scheme: answered HTTP \(response.statusCode)\(target)"
        ))
    }

    /// The callback URL of a redirection that an interception layer forwarded to `URLSession` instead of
    /// refusing it. `URLSession` has no handler for the app's custom scheme, so following such a redirection
    /// ends in `unsupportedURL` — and the URL it failed to load is the callback itself, authorization code
    /// included. Recovering it costs nothing in security: the TLS connection it came from was already made and
    /// validated, and the callback is never loaded.
    ///
    /// The shape of that error is measured on an iOS 26 simulator and on Mac Catalyst, not a documented
    /// contract; a runtime reporting it otherwise gets `nil` here and the raw error.
    private static func callbackFollowedInstead(of error: Error) -> URL? {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain, error.code == NSURLErrorUnsupportedURL else { return nil }

        let failing = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL
            ?? (error.userInfo[NSURLErrorFailingURLStringErrorKey] as? String).flatMap(URL.init(string:))
        guard let failing, failing.hasCustomScheme else { return nil }

        return failing
    }
}

/// The task a ``DataRequest`` is running, so cancelling the calling `Task` cancels the request — which is what
/// `URLSession.data(for:)` does, and what a hand-rolled continuation over `dataTask(with:completionHandler:)`
/// would otherwise drop. Locked because the cancellation can land before `URLSession` has handed the task
/// over, and would then be lost.
private final class RunningTask {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false

    func start(_ task: URLSessionTask) {
        lock.lock()
        self.task = task
        let alreadyCancelled = cancelled
        lock.unlock()

        task.resume()
        if alreadyCancelled { task.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()

        task?.cancel()
    }
}
