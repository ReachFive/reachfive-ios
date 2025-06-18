import Foundation
import Alamofire


extension DataRequest {

    private func isSuccess(_ status: Int?) -> Bool {
        guard let status else {
            return false
        }
        return status >= 200 && status < 300
    }

    private func parseJson<T: Decodable>(json: Data, type: T.Type, decoder: JSONDecoder) -> Result<T, ReachFiveError> {
        do {
            let value = try decoder.decode(type, from: json)
            return .success(value)
        } catch {
            return .failure(.TechnicalError(reason: error.localizedDescription))
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

    func responseJson(decoder: JSONDecoder) async -> Result<(), ReachFiveError> {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, ReachFiveError>, Never>) in
            responseData { responseData in
                switch responseData.result {
                case let .failure(error):
                    continuation.resume(returning: .failure(.TechnicalError(reason: error.localizedDescription)))
                    
                case let .success(data):
                    let status = responseData.response?.statusCode
                    if self.isSuccess(status) {
                        continuation.resume(returning: .success(()))
                    } else {
                        switch self.parseJson(json: data, type: ApiError.self, decoder: decoder) {
                        case .success(let value): continuation.resume(returning: .failure(self.handleResponseStatus(status: status, apiError: value)))
                        case .failure(let error): continuation.resume(returning: .failure(error))
                        }
                    }
                }
            }
        }
    }

    func responseJson<T: Decodable>(type: T.Type, decoder: JSONDecoder) async -> Result<T, ReachFiveError> {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Result<T, ReachFiveError>, Never>) in
            responseData { responseData in
                switch responseData.result {
                case let .failure(error):
                    continuation.resume(returning: .failure(.TechnicalError(reason: error.localizedDescription)))

                case let .success(data):
                    let status = responseData.response?.statusCode
                    if self.isSuccess(status) {
                        continuation.resume(returning: self.parseJson(json: data, type: T.self, decoder: decoder))
                    } else {
                        switch self.parseJson(json: data, type: ApiError.self, decoder: decoder) {
                        case .success(let value): continuation.resume(returning: .failure(self.handleResponseStatus(status: status, apiError: value)))
                        case .failure(let error): continuation.resume(returning: .failure(error))
                        }
                    }
                }
            }
        }
    }
}
