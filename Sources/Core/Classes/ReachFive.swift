import Foundation

enum State {
    case NotInitialized
    case Initialized
}

public typealias PasswordlessCallback = (_ result: Result<AuthToken, ReachFiveError>) -> Void

public typealias MfaCredentialRegistrationCallback = (_ result: Result<Void, ReachFiveError>) -> Void

public typealias AccountRecoveryCallback = (_ result: Result<AccountRecoveryResponse, ReachFiveError>) -> Void

public typealias EmailVerificationCallback = (_ result: Result<Void, ReachFiveError>) -> Void

/// TODO:
/// Tester One-tap account upgrade : https://developer.apple.com/videos/play/wwdc2020/10666/
/// Tester le MFA avec "Securing Logins with iCloud Keychain Verification Codes" https://developer.apple.com/documentation/authenticationservices/securing_logins_with_icloud_keychain_verification_codes
/// ReachFive identity SDK
public class ReachFive: NSObject {
    var passwordlessCallback: PasswordlessCallback?
    var mfaCredentialRegistrationCallback: MfaCredentialRegistrationCallback?
    var accountRecoveryCallback: AccountRecoveryCallback?
    var emailVerificationCallback: EmailVerificationCallback?
    var state: State = .NotInitialized
    public let sdkConfig: SdkConfig
    let providersCreators: [ProviderCreator]
    public let reachFiveApi: ReachFiveApi
    var providers: [Provider] = []
    public internal(set) var scope: [String] = []
    var clientConfig: ClientConfigResponse?
    public let storage: Storage
    let credentialManager: CredentialManager
    // The web login in progress (see ``WebAuthenticationSession``).
    let webAuthSession: WebAuthenticationSession
    public let pkceKey = "PASSWORDLESS_PKCE"

    public init(sdkConfig: SdkConfig, providersCreators: [ProviderCreator] = [], storage: Storage? = nil, sdkInternalConfig: SdkInternalConfig? = nil) {
        self.sdkConfig = sdkConfig
        self.providersCreators = providersCreators
        self.storage = storage ?? UserDefaultsStorage()
        reachFiveApi = ReachFiveApi(sdkConfig: sdkConfig)
        credentialManager = CredentialManager()
        webAuthSession = WebAuthenticationSession(baseScheme: sdkConfig.customScheme, sdkRedirectUri: sdkConfig.redirectUri)

        if let sdkInternalConfig {
            Logger.shared.enabled = sdkInternalConfig.loggingEnabled
        }
    }

    /// The captcha configurations the server declares for this client, empty until ``initialize()``
    /// has fetched the client configuration — and empty too when no captcha protects this client.
    ///
    /// Read it to obtain a token the server will accept: which provider to mint with, under which site
    /// key, for which endpoints, and which actions are allowed. The SDK only forwards the resulting
    /// ``Captcha``; it never reads this itself.
    public var captchaConfigs: [CaptchaConfig] { clientConfig?.captcha ?? [] }

    override public var description: String {
        """
        Config: domain=\(sdkConfig.domain), clientId=\(sdkConfig.clientId)
        Providers: \(providers)
        Scope: \(scope.joined(separator: " "))
        """
    }

    /// Routes an incoming URL to the matching SDK interception (passwordless, MFA, account recovery,
    /// email verification). An URL that matches none of the ``SdkConfig`` URIs falls back to
    /// `interceptPasswordless`, as it always has.
    public func interceptUrl(_ url: URL) {
        if !routeUrl(url) {
            interceptPasswordless(url)
        }
    }

    /// Same routing as ``interceptUrl(_:)``, but reports whether the URL actually matched one of the
    /// ``SdkConfig`` URIs instead of falling back to passwordless.
    /// Used by `application(_:open:)`, which must tell the host app when nothing of ours consumed the URL.
    ///
    /// The matching goes through ``matchesEndpoint(of:)``, the same matcher
    /// `WebAuthenticationSession.isOurCallback` uses, so the two entry hooks can't disagree
    @discardableResult
    func routeUrl(_ url: URL) -> Bool {
        if url.matchesEndpoint(of: sdkConfig.accountRecoveryUri) {
            interceptAccountRecovery(url)
        } else if url.matchesEndpoint(of: sdkConfig.mfaUri) {
            interceptVerifyMfaCredential(url)
        } else if url.matchesEndpoint(of: sdkConfig.redirectUri) {
            interceptPasswordless(url)
        } else if url.matchesEndpoint(of: sdkConfig.emailVerificationUri) {
            interceptEmailVerification(url)
        } else {
            return false
        }
        return true
    }
}
