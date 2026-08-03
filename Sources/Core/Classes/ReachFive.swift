import Foundation

enum State {
    case NotInitialized
    case Initialized
}

public typealias PasswordlessCallback = (_ result: Result<AuthToken, ReachFiveError>) -> Void

public typealias MfaCredentialRegistrationCallback = (_ result: Result<(), ReachFiveError>) -> Void

public typealias AccountRecoveryCallback = (_ result: Result<AccountRecoveryResponse, ReachFiveError>) -> Void

public typealias EmailVerificationCallback = (_ result: Result<(), ReachFiveError>) -> Void

//TODO:
// Tester One-tap account upgrade : https://developer.apple.com/videos/play/wwdc2020/10666/
// Tester le MFA avec "Securing Logins with iCloud Keychain Verification Codes" https://developer.apple.com/documentation/authenticationservices/securing_logins_with_icloud_keychain_verification_codes
// Voir si je peux améliorer l'init/rétention du CredentialManager
/// ReachFive identity SDK
public class ReachFive: NSObject {
    var passwordlessCallback: PasswordlessCallback? = nil
    var mfaCredentialRegistrationCallback: MfaCredentialRegistrationCallback? = nil
    var accountRecoveryCallback: AccountRecoveryCallback? = nil
    var emailVerificationCallback: EmailVerificationCallback? = nil
    var state: State = .NotInitialized
    public let sdkConfig: SdkConfig
    let providersCreators: Array<ProviderCreator>
    public let reachFiveApi: ReachFiveApi
    var providers: [Provider] = []
    public internal(set) var scope: [String] = []
    internal var clientConfig: ClientConfigResponse? = nil
    public let storage: Storage
    let credentialManager: CredentialManager
    // The web login in progress (see ``WebAuthenticationSession``).
    let webAuthSession: WebAuthenticationSession
    public let pkceKey = "PASSWORDLESS_PKCE"

    public init(sdkConfig: SdkConfig, providersCreators: Array<ProviderCreator> = [], storage: Storage? = nil, sdkInternalConfig: SdkInternalConfig? = nil) {
        self.sdkConfig = sdkConfig
        self.providersCreators = providersCreators
        self.storage = storage ?? UserDefaultsStorage()
        self.reachFiveApi = ReachFiveApi(sdkConfig: sdkConfig)
        self.credentialManager = CredentialManager(reachFiveApi: reachFiveApi, storage: self.storage)
        self.webAuthSession = WebAuthenticationSession(baseScheme: sdkConfig.customScheme, sdkRedirectUri: sdkConfig.redirectUri)

        if let sdkInternalConfig {
            Logger.shared.enabled = sdkInternalConfig.loggingEnabled
        }
    }

    public override var description: String {
        """
        Config: domain=\(sdkConfig.domain), clientId=\(sdkConfig.clientId)
        Providers: \(providers)
        Scope: \(scope.joined(separator: " "))
        """
    }

    /// Routes an incoming URL to the matching SDK interception (passwordless, MFA, account recovery,
    /// email verification). An URL that matches none of the ``SdkConfig`` URIs falls back to
    /// `interceptPasswordless`, as it always has.
    public func interceptUrl(_ url: URL) -> () {
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
    internal func routeUrl(_ url: URL) -> Bool {
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
