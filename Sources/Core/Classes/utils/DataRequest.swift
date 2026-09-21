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

    /// Logs the response and hands it back when it is a 2xx. Throws on anything else, with the `ApiError` of
    /// the body decoded into the error whenever the body carries one, and the status code alone otherwise.
    @discardableResult
    private func validate(data: Data, response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw logged(.TechnicalError(reason: "Request without response"))
        }

        logger.log(response: httpResponse, data: data)

        let status = httpResponse.statusCode
        guard isSuccess(status) else {
            // An HTML error page from a proxy, an empty body: not an `ApiError`, and the status is all there is.
            guard let apiError = try? parseJson(json: data, type: ApiError.self) else {
                throw logged(.TechnicalError(reason: "Response with \(status) error code"))
            }
            throw handleResponseStatus(status: status, apiError: apiError)
        }

        return httpResponse
    }

    func responseJson() async throws {
        logger.log(request: request)
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
    }

    func responseJson<T: Decodable>(type: T.Type) async throws -> T {
        logger.log(request: request)
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return try parseJson(json: data, type: T.self)
    }

    /// The `/oauth/authorize` call, whose result is not a response to read but a redirection to the app's
    /// custom scheme: the callback URL, with the authorization code in it.
    ///
    /// ``CustomSchemeRedirectRefusal`` refuses that redirection, so the task ends on the redirect response
    /// itself and the callback is read from its `Location` header.
    func redirect() async throws -> URL {
        logger.log(request: request)
        let (data, response) = try await session.data(for: request)

        if let redirection = response as? HTTPURLResponse, isRedirection(redirection.statusCode) {
            logger.log(response: redirection, data: data)

            let location = redirection.value(forHTTPHeaderField: "Location")
            if let callback = location.flatMap(URL.init(string:)), callback.hasCustomScheme {
                return callback
            }
            let target = location.map { "Location '\($0)'" } ?? "no Location header"
            throw logged(.TechnicalError(
                reason: "Request did not redirect to the app's custom scheme: answered HTTP \(redirection.statusCode) with \(target)"
            ))
        }

        // Anything but a 2xx throws here, its `ApiError` decoded: a rejected `redirect_uri` answers
        // `403 error.client.redirectUrlNotAllowed`.
        let final = try validate(data: data, response: response)
        throw logged(.TechnicalError(
            reason: "Request did not redirect to the app's custom scheme: answered HTTP \(final.statusCode)"
        ))
    }
}
