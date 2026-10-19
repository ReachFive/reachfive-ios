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

    private func handleResponseStatus(status: Int, apiError: ApiError?) -> ReachFiveError {
        let error: ReachFiveError = if status == 400, let apiError {
            .RequestError(apiError: apiError)
        } else if status == 401 {
            .AuthFailure(reason: "Unauthorized", apiError: apiError)
        } else {
            .TechnicalError(reason: "Response with \(status) error code", apiError: apiError)
        }
        return logged(error)
    }

    /// Logs the response and hands it back when it is a 2xx. Throws on anything else, with the `ApiError` of
    /// the body decoded into the error whenever the body carries one, and the status code alone otherwise.
    @discardableResult
    private func validate(data: Data, response: URLResponse?) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw logged(.TechnicalError(reason: "Request ended without a response nor an error"))
        }

        logger.log(response: httpResponse, data: data)

        let status = httpResponse.statusCode
        guard isSuccess(status) else {
            // Decoded without `parseJson`, which would log a decoding failure for an HTML page or an empty body.
            let apiError = try? decoder.decode(ApiError.self, from: data)
            throw handleResponseStatus(status: status, apiError: apiError)
        }

        return httpResponse
    }

    /// Runs the request over the completion handler rather than `URLSession.data(for:)`, whose back-deployed
    /// form traps when a task ends with neither a response nor an error — which a network interception layer
    /// can produce. Cancelling the calling `Task` does not cancel the request: its result is dropped instead.
    private func perform() async throws -> (Data, URLResponse?) {
        try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { [logger] data, response, error in
                if let error {
                    logger.log(error: error)
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data ?? Data(), response))
                }
            }.resume()
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

    /// The `/oauth/authorize` call, whose result is not a response to read but a redirection to its
    /// `redirect_uri`: the callback URL, with the authorization code in it.
    ///
    /// ``CallbackRedirectRefusal`` refuses that redirection, so the task ends on the redirect response
    /// itself and the callback is read from its `Location` header.
    func redirect() async throws -> URL {
        logger.log(request: request)
        let (data, response) = try await perform()

        if let redirection = response as? HTTPURLResponse, isRedirection(redirection.statusCode) {
            logger.log(response: redirection, data: data)

            let location = redirection.value(forHTTPHeaderField: "Location")
            if let callback = location.flatMap(URL.init(string:)), callback.isCallback(of: request.url) {
                return callback
            }
            let target = location.map { "Location '\($0)'" } ?? "no Location header"
            throw logged(.TechnicalError(
                reason: "Request did not redirect to its redirect_uri: answered HTTP \(redirection.statusCode) with \(target)"
            ))
        }

        // Anything but a 2xx throws here, its `ApiError` decoded: a rejected `redirect_uri` answers
        // `403 error.client.redirectUrlNotAllowed`. A 2xx is either the server not redirecting, or a web
        // redirection `URLSession` followed, to a login or error page.
        let final = try validate(data: data, response: response)
        let redirectedTo = final.url.flatMap { $0 == request.url ? nil : " after redirecting to '\($0.absoluteString)'" } ?? ""
        throw logged(.TechnicalError(
            reason: "Request did not redirect to its redirect_uri: answered HTTP \(final.statusCode)\(redirectedTo)"
        ))
    }
}
