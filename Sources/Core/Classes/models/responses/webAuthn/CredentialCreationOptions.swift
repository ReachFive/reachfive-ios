import Foundation

public class CredentialCreationOptions: Codable, DictionaryEncodable {
    public let publicKey: R5PublicKeyCredentialCreationOptions
    
    public init(publicKey: R5PublicKeyCredentialCreationOptions) {
        self.publicKey = publicKey
    }
}
