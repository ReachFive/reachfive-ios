import Foundation

public extension Result {
    init(catching body: () async throws(Failure) -> Success) async {
        do {
            let success = try await body()
            self = .success(success)
        } catch {
            self = .failure(error)
        }
    }

    @discardableResult
    func onSuccess(callback: @escaping (Success) async -> Void) async -> Self {
        if case .success(let value) = self {
            await callback(value)
        }
        return self
    }


    @discardableResult
    func onFailure(callback: @escaping (Failure) async -> Void) async -> Self {
        if case .failure(let value) = self {
            await callback(value)
        }
        return self
    }

    @discardableResult
    func onComplete(callback: @escaping (Self) async -> Void) async -> Self {
        await callback(self)
        return self
    }

}
