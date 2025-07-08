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
}

public extension CheckedContinuation {

    @inlinable
    func resume(catching body: () async throws(E) -> T) async {
        do {
            self.resume(returning: try await body())
        } catch {
            self.resume(throwing: error)
        }
    }
}
