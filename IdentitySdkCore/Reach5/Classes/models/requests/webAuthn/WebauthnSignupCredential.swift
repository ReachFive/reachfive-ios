import Foundation

public class WebauthnSignupCredential: Codable, DictionaryEncodable {
    public var webauthnId: String
    public var publicKeyCredential: RegistrationPublicKeyCredential
    
    public init(webauthnId: String, publicKeyCredential: RegistrationPublicKeyCredential) {
        self.webauthnId = webauthnId
        self.publicKeyCredential = publicKeyCredential
    }
}

