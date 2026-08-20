import Foundation

class DataRequest {
    private let request: URLRequest
    private let session: URLSession
    private let redirectHandler: RedirectHandler
    private let decoder: JSONDecoder
    private let logger = Logger.shared

    init(request: URLRequest, session: URLSession, redirectHandler: RedirectHandler, decoder: JSONDecoder) {
        self.request = request
        self.session = session
        self.redirectHandler = redirectHandler
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
            throw ReachFiveError.TechnicalError(reason: Self.reason(decoding: type, failedWith: error))
        }
    }

    /// A `DecodingError`'s `localizedDescription` is Foundation's generic sentence ("The data couldn't be
    /// read because it isn't in the correct format."), translated into the device's language and naming
    /// neither the field nor the problem — nothing an integrator, or a crash reporter, can act on. The error
    /// carries both, so report them.
    internal static func reason(decoding type: Any.Type, failedWith error: Error) -> String {
        guard let error = error as? DecodingError else { return error.localizedDescription }

        let context: DecodingError.Context
        let problem: String
        switch error {
        case let .dataCorrupted(errorContext):
            context = errorContext
            problem = "unusable value"
        case let .keyNotFound(key, errorContext):
            context = errorContext
            problem = "missing key '\(key.stringValue)'"
        case let .typeMismatch(expected, errorContext):
            context = errorContext
            problem = "expected \(expected)"
        case let .valueNotFound(expected, errorContext):
            context = errorContext
            problem = "no value for \(expected)"
        @unknown default:
            return error.localizedDescription
        }

        // Array elements appear in the path as "Index n", which is what locates the offending item.
        let path = context.codingPath.map(\.stringValue).joined(separator: " → ")
        let at = path.isEmpty ? "" : " at '\(path)'"
        return "Could not decode \(type)\(at): \(problem). \(context.debugDescription)"
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
        let task = session.dataTask(with: request)
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                await redirectHandler.registerContinuation(continuation, for: task.taskIdentifier)
                task.resume()
            }
        }
    }
}
