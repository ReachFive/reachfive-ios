import Foundation

public class SdkConfig {
    public let domain: String
    public let clientId: String

    ///The scheme. Defaults to `reachfive-clientId`
    public let baseScheme: String
    /// The redirect URI for passwordless. Defaults to `reachfive-clientId://callback`
    public let redirectUri: URL
    /// The redirect URI for MFA. Defaults to `reachfive-clientId://mfa`
    public let mfaUri: URL
    /// The redirect URI for Account Recovery. Defaults to `reachfive-clientId://account-recovery`
    public let accountRecoveryUri: URL
    /// The redirect URI for email verification. Defaults to `reachfive-clientId://email-verification`
    public let emailVerificationUri: URL

    public init(
        domain: String,
        clientId: String,
        baseScheme: String? = nil,
        redirectUri: URL? = nil,
        mfaUri: URL? = nil,
        accountRecoveryUri: URL? = nil,
        emailVerificationUri: URL? = nil
    ) throws {
        self.domain = domain
        self.clientId = clientId

        let resolvedBaseScheme = baseScheme ?? "reachfive-\(clientId)"
        self.baseScheme = resolvedBaseScheme

        func parseUrl(_ url: URL?, defaultString: String) throws -> URL {
            if let url {
                return url
            }
            guard let parsedUrl = URL(string: defaultString) else {
                throw ReachFiveError.TechnicalError(reason: "Unable to construct SdkConfig default URL for value: \(defaultString)")
            }
            return parsedUrl
        }

        self.redirectUri = try parseUrl(redirectUri, defaultString: "\(resolvedBaseScheme)://callback")
        self.mfaUri = try parseUrl(mfaUri, defaultString: "\(resolvedBaseScheme)://mfa")
        self.emailVerificationUri = try parseUrl(emailVerificationUri, defaultString: "\(resolvedBaseScheme)://email-verification")
        self.accountRecoveryUri = try parseUrl(accountRecoveryUri, defaultString: "\(resolvedBaseScheme)://account-recovery")
    }
}
