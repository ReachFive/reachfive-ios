import Foundation

public class R5PublicKeyCredentialUserEntity: Codable, DictionaryEncodable {
    public var id: String
    public var displayName: String
    public var name: String
    
    public init(id: String, displayName: String, name: String) {
        self.id = id
        self.displayName = displayName
        self.name = name
    }
}
