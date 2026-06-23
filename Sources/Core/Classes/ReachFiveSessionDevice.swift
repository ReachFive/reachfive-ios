import Foundation

public extension ReachFive {
    func deleteSessionDevice(id: String, authToken: AuthToken) async throws {
        return try await reachFiveApi.deleteSessionDevice(id: id, authToken: authToken)
    }
    
    func listSessionDevices(authToken: AuthToken) async throws -> [SessionDevice] {
        return try await reachFiveApi.listSessionDevices(authToken: authToken).sessionDevices
    }
}
