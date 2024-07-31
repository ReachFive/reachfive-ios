import Foundation

public class DeviceCredential: Codable, DictionaryEncodable {
    public let friendlyName: String
    public let id: String
    
    public init(friendlyName: String, id: String) {
        self.friendlyName = friendlyName
        self.id = id
    }
}

