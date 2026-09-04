import Foundation

public class LoginRequest: Codable, DictionaryEncodable {
    public let email: String?
    public let phoneNumber: String?
    public let customIdentifier: String?
    public let password: String
    public let grantType: String
    public let clientId: String
    public let scope: String
    public let origin: String?
    public let captchaToken: String?
    public let captchaProvider: CaptchaProvider?

    public init(email: String?, phoneNumber: String?, customIdentifier: String?, password: String, grantType: String, clientId: String, scope: String, origin: String? = nil, captcha: Captcha? = nil) {
        self.email = email
        self.phoneNumber = phoneNumber
        self.customIdentifier = customIdentifier
        self.password = password
        self.grantType = grantType
        self.clientId = clientId
        self.scope = scope
        self.origin = origin
        captchaToken = captcha?.token
        captchaProvider = captcha?.provider
    }
}
