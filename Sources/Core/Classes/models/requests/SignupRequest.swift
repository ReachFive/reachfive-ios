import Foundation

public class SignupRequest: Codable, DictionaryEncodable {
    public let clientId: String
    public let data: ProfileSignupRequest
    public let scope: String
    public let redirectUrl: URL?
    public let origin: String?
    public let captchaToken: String?
    public let captchaProvider: CaptchaProvider?

    public init(clientId: String, data: ProfileSignupRequest, scope: String, redirectUrl: URL?, origin: String? = nil, captcha: Captcha? = nil) {
        self.clientId = clientId
        self.data = data
        self.scope = scope
        self.redirectUrl = redirectUrl
        self.origin = origin
        captchaToken = captcha?.token
        captchaProvider = captcha?.provider
    }
}
