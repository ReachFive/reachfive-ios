import Foundation

extension CheckedContinuation {
    @inlinable
    public func resume(catching body: @escaping () async throws(E) -> T) {
        Task {
            do {
                try await self.resume(returning: body())
            } catch {
                self.resume(throwing: error as! E)
            }
        }
    }
}
