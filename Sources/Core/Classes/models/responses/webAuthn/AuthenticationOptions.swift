import Foundation

public class AuthenticationOptions: Codable, DictionaryEncodable {
    public let publicKey: R5PublicKeyCredentialRequestOptions
    
    public init(publicKey: R5PublicKeyCredentialRequestOptions) {
        self.publicKey = publicKey
    }
}
