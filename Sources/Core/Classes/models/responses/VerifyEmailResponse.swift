import Foundation

public class SendEmailVerificationResponse: Codable, DictionaryEncodable {
    public let verificationEmailSent: Bool
}
