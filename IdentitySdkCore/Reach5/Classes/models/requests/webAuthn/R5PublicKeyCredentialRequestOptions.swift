import Foundation

public class R5PublicKeyCredentialRequestOptions: Codable, DictionaryEncodable {
    public var challenge: String
    public var timeout: Int? = nil
    public var rpId: String
    public var allowCredentials: [R5PublicKeyCredentialDescriptor]? = nil
    public var userVerification: String
    
    public init(challenge: String, timeout: Int?, rpId: String, allowCredentials: [R5PublicKeyCredentialDescriptor]?, userVerification: String) {
        self.challenge = challenge
        self.timeout = timeout
        self.rpId = rpId
        self.allowCredentials = allowCredentials
        self.userVerification = userVerification
    }
}


