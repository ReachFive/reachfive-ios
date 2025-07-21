import Foundation

class DataRequest {
    private let request: URLRequest
    private let session: URLSession
    private let redirectHandler: RedirectHandler
    private let decoder: JSONDecoder

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
            return try decoder.decode(type, from: json)
        } catch {
            throw ReachFiveError.TechnicalError(reason: error.localizedDescription)
        }
    }

    private func handleResponseStatus(status: Int, apiError: ApiError) -> ReachFiveError {
        if status == 400 {
            return .RequestError(apiError: apiError)
        }
        if status == 401 {
            return .AuthFailure(reason: "Unauthorized", apiError: apiError)
        }
        return .TechnicalError(
            reason: "Response with \(status) error code",
            apiError: apiError
        )
    }

    func responseJson() async throws {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReachFiveError.TechnicalError(reason: "Request without response")
        }

        let status = httpResponse.statusCode
        if !isSuccess(status) {
            let apiError = try parseJson(json: data, type: ApiError.self)
            throw handleResponseStatus(status: status, apiError: apiError)
        }
    }

    func responseJson<T: Decodable>(type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let response = response as? HTTPURLResponse else {
            throw ReachFiveError.TechnicalError(reason: "Request without response")
        }

        let status = response.statusCode
        guard isSuccess(status) else {
            let apiError = try parseJson(json: data, type: ApiError.self)
            throw handleResponseStatus(status: status, apiError: apiError)
        }

        return try parseJson(json: data, type: T.self)
    }

    func redirect() async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            redirectHandler.redirectContinuation = continuation
            Task {
                _ = try await session.data(for: request)
            }
        }
    }
}
