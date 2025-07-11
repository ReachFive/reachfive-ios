import Foundation

enum State {
    case NotInitialized
    case Initialized
}

public typealias PasswordlessCallback = (_ result: Result<AuthToken, ReachFiveError>) -> Void

public typealias MfaCredentialRegistrationCallback = (_ result: Result<(), ReachFiveError>) -> Void

public typealias AccountRecoveryCallback = (_ result: Result<AccountRecoveryResponse, ReachFiveError>) -> Void

public typealias EmailVerificationCallback = (_ result: Result<(), ReachFiveError>) -> Void

//TODO
// Tester One-tap account upgrade : https://developer.apple.com/videos/play/wwdc2020/10666/
// Tester le MFA avec "Securing Logins with iCloud Keychain Verification Codes" https://developer.apple.com/documentation/authenticationservices/securing_logins_with_icloud_keychain_verification_codes
// Apparemment les custom scheme sont dépréciés et il faudrait utiliser les "Universal Links" : https://developer.apple.com/ios/universal-links/
/// ReachFive identity SDK
public class ReachFive: NSObject {
    var passwordlessCallback: PasswordlessCallback? = nil
    var mfaCredentialRegistrationCallback: MfaCredentialRegistrationCallback? = nil
    var accountRecoveryCallback: AccountRecoveryCallback? = nil
    var emailVerificationCallback: EmailVerificationCallback? = nil
    var state: State = .NotInitialized
    public let sdkConfig: SdkConfig
    let providersCreators: Array<ProviderCreator>
    let reachFiveApi: ReachFiveApi
    var providers: [Provider] = []
    internal var scope: [String] = []
    internal var clientConfig: ClientConfigResponse? = nil
    public let storage: Storage
    let credentialManager: CredentialManager
    public let pkceKey = "PASSWORDLESS_PKCE"
    
    public init(sdkConfig: SdkConfig, providersCreators: Array<ProviderCreator> = [], storage: Storage? = nil) {
        self.sdkConfig = sdkConfig
        self.providersCreators = providersCreators
        self.reachFiveApi = ReachFiveApi(sdkConfig: sdkConfig)
        self.storage = storage ?? UserDefaultsStorage()
        self.credentialManager = CredentialManager(reachFiveApi: reachFiveApi, storage: self.storage)
    }
    
    public override var description: String {
        """
        Config: domain=\(sdkConfig.domain), clientId=\(sdkConfig.clientId)
        Providers: \(providers)
        Scope: \(scope.joined(separator: " "))
        """
    }
        
    public func interceptUrl(_ url: URL) -> () {
        let receivedUrl = URLComponents(url: url, resolvingAgainstBaseURL: true)
        
        let recovery = URLComponents(string: sdkConfig.accountRecoveryUri)
        let mfa = URLComponents(string: sdkConfig.mfaUri)
        let passwordless = URLComponents(string: sdkConfig.redirectUri)
        let emailVerification = URLComponents(string: sdkConfig.emailVerificationUri)
        
        switch (receivedUrl?.host, receivedUrl?.path) {
        
        case (recovery?.host, recovery?.path): interceptAccountRecovery(url)
        case (mfa?.host, mfa?.path): interceptVerifyMfaCredential(url)
        case (passwordless?.host, passwordless?.path): interceptPasswordless(url)
        case (emailVerification?.host, emailVerification?.path): interceptEmailVerification(url)
            
            // fallback to old way of doing things if url components are not properly extracted
        case ("account-recovery", _): interceptAccountRecovery(url)
        case ("mfa", _): interceptVerifyMfaCredential(url)
        case ("callback", _): interceptPasswordless(url)
        
        default: interceptPasswordless(url)
        }
    }
}
