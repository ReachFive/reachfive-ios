import Foundation

extension ReachFive {
    public func deleteSessionDevice(id: String, authToken: AuthToken) async throws {
        try await reachFiveApi.deleteSessionDevice(id: id, authToken: authToken)
    }

    public func listSessionDevices(authToken: AuthToken) async throws -> [SessionDevice] {
        try await reachFiveApi.listSessionDevices(authToken: authToken).sessionDevices
    }
}
