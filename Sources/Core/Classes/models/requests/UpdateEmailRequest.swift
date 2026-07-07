import Foundation

public class UpdateEmailRequest: Codable, DictionaryEncodable {
    public let email: String
    public let redirectUrl: URL?

    public init(email: String, redirectUrl: URL?) {
        self.email = email
        self.redirectUrl = redirectUrl
    }
}
