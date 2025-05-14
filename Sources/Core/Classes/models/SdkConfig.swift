import Foundation

public class SdkConfig {
    public let domain: String
    public let clientId: String
    
    /// Alias for the `redirectUri`
    public let scheme: String
    
    ///The scheme. Defaults to `reachfive-clientId`
    public let baseScheme: String
    /// The redirect URI for passwordless. Defaults to `reachfive-clientId://callback`
    public let redirectUri: String
    /// The redirect URI for MFA. Defaults to `reachfive-clientId://mfa`
    public let mfaUri: String
    /// The redirect URI for Account Recovery. Defaults to `reachfive-clientId://account-recovery`
    public let accountRecoveryUri: String
    /// The redirect URI for email verification. Defaults to `reachfive-clientId://email-verification`
    public let emailVerificationUri: String
    
    public init(domain: String, clientId: String, scheme: String? = nil, baseScheme: String? = nil, mfaUri: String? = nil, accountRecoveryUri: String? = nil, emailVerificationUri: String? = nil) {
        self.domain = domain
        self.clientId = clientId
        self.baseScheme = baseScheme ?? "reachfive-\(clientId)"
        self.scheme = scheme ?? "\(self.baseScheme)://callback"
        self.redirectUri = self.scheme
        self.mfaUri = mfaUri ?? "\(self.baseScheme)://mfa"
        self.emailVerificationUri = emailVerificationUri ?? "\(self.baseScheme)://email-verification"
        self.accountRecoveryUri = accountRecoveryUri ?? "\(self.baseScheme)://account-recovery"
    }
}
