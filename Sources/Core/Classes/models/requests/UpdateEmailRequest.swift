import Foundation

public class UpdateEmailRequest: Codable, DictionaryEncodable {
    public let email: String
    public let redirectUrl: URL?
    public let captchaToken: String?
    public let captchaProvider: CaptchaProvider?

    public init(email: String, redirectUrl: URL?, captcha: Captcha? = nil) {
        self.email = email
        self.redirectUrl = redirectUrl
        captchaToken = captcha?.token
        captchaProvider = captcha?.provider
    }
}
