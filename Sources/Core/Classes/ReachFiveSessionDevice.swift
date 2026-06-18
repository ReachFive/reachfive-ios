import Foundation

public extension ReachFive {
    func listSessionDevices(authToken: AuthToken) async throws -> [SessionDevice] {
        return try await reachFiveApi.listSessionDevices(authToken: authToken).sessionDevices
    }
}
