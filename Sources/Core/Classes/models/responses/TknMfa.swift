import Foundation

public class TknMfa: Codable, DictionaryEncodable {
    public let tkn: String
    public let mfaRequired: Bool?
}
