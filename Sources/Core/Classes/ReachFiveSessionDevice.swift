import Foundation

public extension ReachFive {
    func listSessionDevices(authToken: AuthToken) async throws -> ListSessionDevices {
        return try await reachFiveApi.listSessionDevices(authToken: authToken)
    }
    
    func deleteSessionDevice(id: String, authToken: AuthToken) async throws {
        return try await reachFiveApi.deleteSessionDevice(id: id, authToken: authToken)
    }
}
