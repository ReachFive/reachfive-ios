import Foundation

/// A captcha token the application obtained, forwarded as is to the ReachFive server.
///
/// The SDK never produces the token: obtaining one is the application's job, because every captcha
/// service ReachFive verifies mints its tokens in a web context (`grecaptcha.execute` for reCAPTCHA,
/// the CaptchaFox widget) and the SDK ships no web view of its own.
///
/// Two properties of a token decide whether the call it accompanies succeeds, and neither is visible
/// from here:
/// - it is **single-use and short-lived** — two minutes for reCAPTCHA — so obtain it immediately
///   before the call rather than ahead of time, and never reuse it for a second call;
/// - the **action** it was minted with is sealed inside it. The server compares that action against
///   the ones configured for the client, so a token minted for `login` is refused on a signup as
///   soon as the client declares its actions. There is no action parameter to pass here: choose it
///   when you mint the token.
///
/// Captcha verification is entirely driven by the client's configuration in the ReachFive console. A
/// token sent to an endpoint with no captcha configured is ignored, and conversely an endpoint with
/// a captcha configured refuses a call that carries no token.
public struct Captcha: Equatable {
    /// The token as the captcha service returned it, uninterpreted.
    public let token: String

    /// Which service minted `token`. Always sent along with it: when the server is left to guess, it
    /// runs every configured verifier and all of them must pass, so a reCAPTCHA token would be
    /// submitted to CaptchaFox as well.
    public let provider: CaptchaProvider

    public init(token: String, provider: CaptchaProvider) {
        self.token = token
        self.provider = provider
    }
}

/// The captcha services the ReachFive server knows how to verify.
///
/// A `struct` rather than an `enum`: the server gaining a provider must not require an SDK release
/// before an application can name it. Use ``reCaptcha`` or ``captchaFox``, or
/// ``init(rawValue:)`` for one this version does not know yet.
public struct CaptchaProvider: RawRepresentable, Codable, Equatable {
    /// The provider name as the ReachFive API spells it, sent as the `captcha_provider` parameter.
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Google reCAPTCHA, verified against `siteverify` — so a token minted by a **website** key.
    /// Tokens from Google's native iOS SDK belong to reCAPTCHA Enterprise and are verified through a
    /// different API, which ReachFive does not call: they are refused here.
    public static let reCaptcha = CaptchaProvider(rawValue: "recaptcha")

    /// CaptchaFox, verified against its own `siteverify`.
    public static let captchaFox = CaptchaProvider(rawValue: "captchafox")
}
