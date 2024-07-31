import Foundation

public class UpdateEmailRequest: Codable, DictionaryEncodable {
    public let email: String
    public let redirectUrl: String?
    
    public init(email: String, redirectUrl: String?) {
        self.email = email
        self.redirectUrl = redirectUrl
    }
}
