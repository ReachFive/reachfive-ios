import Foundation

public class RegistrationRequest: Codable, DictionaryEncodable {
    public let origin: String
    public let friendlyName: String
    
    public init(origin: String, friendlyName: String) {
        self.origin = origin
        self.friendlyName = friendlyName
    }
}
