import Foundation

public class ClientConfigResponse: Codable {
    public let scope: String
    public let sms: Bool

    /// The captcha configurations active for this client, absent when there is none. See
    /// ``CaptchaConfig``.
    public let captcha: [CaptchaConfig]?

    public init(scope: String, sms: Bool, captcha: [CaptchaConfig]? = nil) {
        self.scope = scope
        self.sms = sms
        self.captcha = captcha
    }
}
