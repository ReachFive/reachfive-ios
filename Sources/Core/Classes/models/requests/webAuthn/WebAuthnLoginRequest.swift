import Foundation

public struct WebAuthnLoginRequest: Codable, DictionaryEncodable {
    public let clientId: String
    public let origin: String
    public let email: String?
    public let phoneNumber: String?
    public let scope: String

    /// - Parameter username: the identifier the server needs for a non-discoverable login. Stays nil for
    ///   the flows where the user picks a credential (auto-fill, modal sheet).
    public init(clientId: String, origin: String, username: Username? = nil, scope: [String]? = nil) {
        self.clientId = clientId
        self.origin = origin
        email = username?.email
        phoneNumber = username?.phoneNumber
        self.scope = (scope ?? []).joined(separator: " ")
    }
}
