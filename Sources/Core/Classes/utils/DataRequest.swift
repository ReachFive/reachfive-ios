import Foundation
import Alamofire


extension DataRequest {

    private func isSuccess(_ status: Int?) -> Bool {
        guard let status else {
            return false
        }
        return status >= 200 && status < 300
    }

    private func parseJson<T: Decodable>(json: Data, type: T.Type, decoder: JSONDecoder) throws -> T {
        do {
            return try decoder.decode(type, from: json)
        } catch {
            throw ReachFiveError.TechnicalError(reason: error.localizedDescription)
        }
    }

    private func handleResponseStatus(status: Int?, apiError: ApiError) -> ReachFiveError {
        guard let status else {
            return .TechnicalError(
                reason: "Technical error: Request without error code",
                apiError: apiError)
        }
        if status == 400 {
            return .RequestError(apiError: apiError)
        }
        if status == 401 {
            return .AuthFailure(reason: "Unauthorized", apiError: apiError)
        }
        return .TechnicalError(
            reason: "Technical error: Request with \(status) error code",
            apiError: apiError
        )
    }

    func responseJson(decoder: JSONDecoder) async throws -> Void {
        return try await withCheckedThrowingContinuation { continuation in
            responseData { responseData in
                switch responseData.result {
                case let .failure(error):
                    continuation.resume(throwing: ReachFiveError.TechnicalError(reason: error.localizedDescription))

                case let .success(data):
                    let status = responseData.response?.statusCode
                    if self.isSuccess(status) {
                        continuation.resume(returning: ())
                    } else {
                        do {
                            let apiError = try self.parseJson(json: data, type: ApiError.self, decoder: decoder)
                            continuation.resume(throwing: self.handleResponseStatus(status: status, apiError: apiError))
                        } catch {
                            continuation.resume(throwing: error)
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
                    let status = responseData.response?.statusCode
                    do {
                        if self.isSuccess(status) {
                            continuation.resume(returning: try self.parseJson(json: data, type: T.self, decoder: decoder))
                        } else {
                            let apiError = try self.parseJson(json: data, type: ApiError.self, decoder: decoder)
                            continuation.resume(throwing: self.handleResponseStatus(status: status, apiError: apiError))
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

