import Foundation

public class R5PublicKeyCredentialParameter: Codable, DictionaryEncodable {
    public var alg: Int
    public var type: String
    
    public init(alg: Int, type: String) {
        self.alg = alg
        self.type = type
    }
}
