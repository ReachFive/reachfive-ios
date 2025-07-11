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
    func resume(catching body: @escaping () async throws(E) -> T) {
        Task {
            do {
                self.resume(returning: try await body())
            } catch {
                self.resume(throwing: error as! E)
            }
        }
    }
}
