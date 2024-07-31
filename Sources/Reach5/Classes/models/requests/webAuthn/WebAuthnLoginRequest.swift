import Foundation

public class WebAuthnLoginRequest: Codable, DictionaryEncodable {
    public var clientId: String
    public var origin: String
    public var email: String?
    public var phoneNumber: String?
    public var scope: String
    
    public init(clientId: String, origin: String, scope: [String]? = nil) {
        self.clientId = clientId
        self.origin = origin
        self.scope = (scope ?? []).joined(separator: " ")
    }
}

