import Foundation

public class RegistrationOptions: Codable, DictionaryEncodable {
    public let friendlyName: String
    public let options: CredentialCreationOptions
    
    public init(friendlyName: String, options: CredentialCreationOptions) {
        self.friendlyName = friendlyName
        self.options = options
    }
}
