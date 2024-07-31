import Foundation

public class R5AuthenticatorAssertionResponse: Codable, DictionaryEncodable {
    public var authenticatorData: String
    public var clientDataJSON: String
    public var signature: String
    public var userHandle: String? = nil
    
    public init(authenticatorData: String, clientDataJSON: String, signature: String, userHandle: String?) {
        self.authenticatorData = authenticatorData
        self.clientDataJSON = clientDataJSON
        self.signature = signature
        self.userHandle = userHandle
    }
}

