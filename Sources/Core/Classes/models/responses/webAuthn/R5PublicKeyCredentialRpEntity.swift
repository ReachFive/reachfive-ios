import Foundation

public class R5PublicKeyCredentialRpEntity: Codable, DictionaryEncodable {
    public var id: String
    public var name: String
    
    
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
