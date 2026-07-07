import Foundation

public class SendEmailVerificationRequest: Codable, DictionaryEncodable {
    public let redirectUrl: URL?

    public init(redirectUrl: URL? = nil) {
        self.redirectUrl = redirectUrl
    }
}

public class VerifyEmailRequest: Codable, DictionaryEncodable {
    public let email: String
    public let verificationCode: String

    public init(email: String, verificationCode: String) {
        self.email = email
        self.verificationCode = verificationCode
    }

}
