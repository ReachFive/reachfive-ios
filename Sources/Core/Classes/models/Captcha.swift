import Foundation

/// A captcha token together with the provider that issued it. The pair is sent as-is to the API,
/// which verifies it against the provider the account has enabled (Console > Security > Captcha).
public struct Captcha: Equatable {
    public let token: String

    /// Which service minted `token`
    public let provider: CaptchaProvider

    public init(token: String, provider: CaptchaProvider) {
        self.token = token
        self.provider = provider
    }
}

public struct CaptchaProvider: RawRepresentable, Codable, Equatable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let reCaptcha = CaptchaProvider(rawValue: "recaptcha")

    public static let captchaFox = CaptchaProvider(rawValue: "captchafox")
}
