import Foundation

public class Emails: Codable, DictionaryEncodable {
    public let verified: [String]?
    public let unverified: [String]?
    
    public init(verified: [String]?, unverified: [String]?) {
        self.verified = verified
        self.unverified = unverified
    }
}
