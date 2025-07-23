import Foundation

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
