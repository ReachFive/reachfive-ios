import Foundation
import Alamofire

extension DataRequest {

    private func isSuccess(_ status: Int) -> Bool {
        status >= 200 && status < 300
    }

    private func parseJson<T: Decodable>(json: Data, type: T.Type, decoder: JSONDecoder) throws(ReachFiveError) -> T {
        do {
            return try decoder.decode(type, from: json)
        } catch {
            throw .TechnicalError(reason: error.localizedDescription)
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

    func responseJson(decoder: JSONDecoder) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            responseData { responseData in
                switch responseData.result {
                case let .failure(error):
                    continuation.resume(throwing: ReachFiveError.TechnicalError(reason: error.localizedDescription))

                case let .success(data):
                    guard let response = responseData.response else {
                        continuation.resume(throwing: ReachFiveError.TechnicalError(reason: "Request without response"))
                        return
                    }

                    let status = response.statusCode
                    continuation.resume {
                        if !self.isSuccess(status) {
                            let apiError = try self.parseJson(json: data, type: ApiError.self, decoder: decoder)
                            throw self.handleResponseStatus(status: status, apiError: apiError)
                        }
                    }
                }
            }
        }
    }

    func responseJson<T: Decodable>(type: T.Type, decoder: JSONDecoder) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            responseData { responseData in
                switch responseData.result {
                case let .failure(error):
                    continuation.resume(throwing: ReachFiveError.TechnicalError(reason: error.localizedDescription))

                case let .success(data):
                    guard let response = responseData.response else {
                        continuation.resume(throwing: ReachFiveError.TechnicalError(reason: "Request without response"))
                        return
                    }

                    let status = response.statusCode
                    continuation.resume {
                        guard self.isSuccess(status) else {
                            let apiError = try self.parseJson(json: data, type: ApiError.self, decoder: decoder)
                            throw self.handleResponseStatus(status: status, apiError: apiError)
                        }

                        return try self.parseJson(json: data, type: T.self, decoder: decoder)
                    }
                }
            }
        }
    }
}

