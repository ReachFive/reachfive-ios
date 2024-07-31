import Foundation

public class AuthenticationToken: Codable, DictionaryEncodable {
    public let tkn: String
    
    public init(tkn: String) {
        self.tkn = tkn
    }
}
