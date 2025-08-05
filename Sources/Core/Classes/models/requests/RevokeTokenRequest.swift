import Foundation

public struct RevokeTokenRequest: Encodable {
    let token: String
    let tokenTypeHint: String?
    let clientId: String

    enum CodingKeys: String, CodingKey {
        case token
        case tokenTypeHint = "token_type_hint"
        case clientId = "client_id"
    }

    func dictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "token": token,
            "client_id": clientId
        ]
        if let tokenTypeHint = tokenTypeHint {
            dict["token_type_hint"] = tokenTypeHint
        }
        return dict
    }
}
