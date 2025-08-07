import Foundation

public struct RevokeTokenRequest: Codable, DictionaryEncodable {
    let token: String
    let tokenTypeHint: String?
    let clientId: String
}
