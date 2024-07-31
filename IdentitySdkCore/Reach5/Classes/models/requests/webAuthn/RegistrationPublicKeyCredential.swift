import Foundation

public class RegistrationPublicKeyCredential: Codable, DictionaryEncodable {
    public var id: String
    public var rawId: String
    public var type: String
    public var response: R5AuthenticatorAttestationResponse
    
    public init(id: String, rawId: String, type: String, response: R5AuthenticatorAttestationResponse) {
        self.id = id
        self.rawId = rawId
        self.type = type
        self.response = response
    }
}

