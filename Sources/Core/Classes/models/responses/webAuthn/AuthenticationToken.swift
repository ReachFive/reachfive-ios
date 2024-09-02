import Foundation

public class AuthenticationToken: Codable, DictionaryEncodable {
    public let tkn: String
    public let mfaRequired: Bool

    public init(tkn: String, mfaRequired: Bool = false) {
        self.tkn = tkn
        self.mfaRequired = mfaRequired
    }
}
