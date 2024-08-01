import Foundation

public class R5AuthenticatorAttestationResponse: Codable, DictionaryEncodable {
    public var attestationObject: String
    public var clientDataJSON: String
    
    public init(attestationObject: String, clientDataJSON: String) {
        self.attestationObject = attestationObject
        self.clientDataJSON = clientDataJSON
    }
}
