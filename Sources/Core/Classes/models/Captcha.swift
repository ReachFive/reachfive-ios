import Foundation

/// A captcha token the application obtained, forwarded as is to the ReachFive server.
///
/// The SDK never produces one: both services ReachFive verifies mint their tokens in a web context,
/// and the SDK ships no web view. A token is single-use, lasts about two minutes, and seals the action
/// it was minted with — hence no action parameter here.
public struct Captcha: Equatable {
    /// The token as the captcha service returned it, uninterpreted.
    public let token: String

    /// Which service minted `token`. Always sent along with it: left to guess, the server runs every
    /// verifier configured for the client and all of them must pass.
    public let provider: CaptchaProvider

    public init(token: String, provider: CaptchaProvider) {
        self.token = token
        self.provider = provider
    }
}

/// The captcha services the ReachFive server knows how to verify.
///
/// A `struct` rather than an `enum` so that a service the server verifies through this same
/// `captcha_token` + `captcha_provider` pair can be named without waiting for an SDK release. One
/// needing anything more would need a new API here anyway.
public struct CaptchaProvider: RawRepresentable, Codable, Equatable {
    /// The provider name as the ReachFive API spells it, sent as the `captcha_provider` parameter.
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Google reCAPTCHA, verified against `siteverify` — so a token minted by a **website** key. Tokens
    /// from Google's native iOS SDK belong to reCAPTCHA Enterprise, verified through another API that
    /// ReachFive does not call: they are refused here.
    public static let reCaptcha = CaptchaProvider(rawValue: "recaptcha")

    /// CaptchaFox, verified against its own `siteverify`.
    public static let captchaFox = CaptchaProvider(rawValue: "captchafox")
}

/// One captcha configuration the ReachFive server declares for this client, as returned by
/// `/identity/v1/config` and read through ``ReachFive/captchaConfigs``.
///
/// The SDK does nothing with it: it neither loads a widget nor mints a token. An application reads it
/// to load the right widget with the right key, and to pick an action the server will accept — the two
/// things it would otherwise have to hardcode per environment.
///
/// The server never exposes the secret half of the pair, nor the score threshold.
public struct CaptchaConfig: Codable, Equatable {
    /// The service to name in ``Captcha/provider``.
    public let provider: CaptchaProvider

    /// `v2` or `v3` for reCAPTCHA, deciding which widget the page loads. Absent for a provider the
    /// notion does not apply to.
    public let version: String?

    /// The public key that loads the widget.
    public let siteKey: String

    /// The endpoints this configuration protects, spelled as the ReachFive console spells them:
    /// `password_login`, `signup`, `signup_token`, `forgot_password`, `passwordless`, `update_email`.
    public let endpoints: [String]

    /// The actions the server accepts. Absent or empty means it validates none — the same meaning the
    /// console gives an empty list.
    public let actions: [String]?

    public init(provider: CaptchaProvider, version: String? = nil, siteKey: String, endpoints: [String] = [], actions: [String]? = nil) {
        self.provider = provider
        self.version = version
        self.siteKey = siteKey
        self.endpoints = endpoints
        self.actions = actions
    }
}
