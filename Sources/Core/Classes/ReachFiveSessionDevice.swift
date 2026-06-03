import Foundation

public extension ReachFive {
    func listSessionDevices(authToken: AuthToken) async throws -> ListSessionDevices {
        return try await reachFiveApi.listSessionDevices(authToken: authToken)
    }
}
