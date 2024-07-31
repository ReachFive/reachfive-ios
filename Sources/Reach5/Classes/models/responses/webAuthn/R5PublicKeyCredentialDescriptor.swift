import Foundation

public class R5PublicKeyCredentialDescriptor: Codable, DictionaryEncodable {
    public var type: String
    public var id: String
    public var transports: [String]? = nil
    
    public init(type: String, id: String, transports: [String]? = nil) {
        self.type = type
        self.id = id
        self.transports = transports
    }
}
