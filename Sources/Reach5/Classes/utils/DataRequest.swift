import Foundation
import Alamofire
import BrightFutures

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
    
    func responseJson(decoder: JSONDecoder) -> Future<(), ReachFiveError> {
        let promise = Promise<(), ReachFiveError>()
        responseData { responseData in
            switch responseData.result {
            case let .failure(error):
                promise.failure(.TechnicalError(reason: error.localizedDescription))
            
            case let .success(data):
                let status = responseData.response?.statusCode
                if self.isSuccess(status) {
                    promise.success(())
                } else {
                    switch self.parseJson(json: data, type: ApiError.self, decoder: decoder) {
                    case .success(let value): promise.failure(self.handleResponseStatus(status: status, apiError: value))
                    case .failure(let error): promise.failure(error)
                    }
                }
            }
        }
        return promise.future
    }
    
    func responseJson<T: Decodable>(type: T.Type, decoder: JSONDecoder) -> Future<T, ReachFiveError> {
        let promise = Promise<T, ReachFiveError>()
        
        responseData { responseData in
            switch responseData.result {
            case let .failure(error):
                promise.failure(.TechnicalError(reason: error.localizedDescription))
            
            case let .success(data):
                let status = responseData.response?.statusCode
                if self.isSuccess(status) {
                    promise.tryComplete(self.parseJson(json: data, type: T.self, decoder: decoder))
                } else {
                    switch self.parseJson(json: data, type: ApiError.self, decoder: decoder) {
                    case .success(let value): promise.failure(self.handleResponseStatus(status: status, apiError: value))
                    case .failure(let error): promise.failure(error)
                    }
                }
            }
        }
        
        return promise.future
    }
}
