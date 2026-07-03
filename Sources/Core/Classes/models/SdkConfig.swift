import Foundation

public class SdkConfig {
    public let domain: String
    public let clientId: String

    ///The scheme. Defaults to `reachfive-clientId`
    public let customScheme: String
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
        customScheme: String? = nil,
        redirectUri: URL? = nil,
        mfaUri: URL? = nil,
        accountRecoveryUri: URL? = nil,
        emailVerificationUri: URL? = nil
    ) throws {
        self.domain = domain
        self.clientId = clientId

        let resolvedScheme = customScheme ?? "reachfive-\(clientId)"

        // Broad scheme validation based on RFC 3986 generic parser rules:
        // Must start with a letter and contain any character except `:`, `/`, `?`, `#`, or whitespace.
        let schemeRegex = "^[a-zA-Z][^:/?#\\s]*$"
        guard resolvedScheme.range(of: schemeRegex, options: .regularExpression) != nil else {
            throw ReachFiveError.TechnicalError(reason: "Invalid scheme format: '\(resolvedScheme)'. A URL scheme must start with a letter and must not contain colons, slashes, question marks, hash symbols, or whitespace.")
        }

        self.customScheme = resolvedScheme

        // Since resolvedBaseScheme is validated under generic URI parsing rules, the following URL constructions are guaranteed to succeed
        self.redirectUri = redirectUri ?? URL(string: "\(resolvedScheme)://callback")!
        self.mfaUri = mfaUri ?? URL(string: "\(resolvedScheme)://mfa")!
        self.emailVerificationUri = emailVerificationUri ?? URL(string: "\(resolvedScheme)://email-verification")!
        self.accountRecoveryUri = accountRecoveryUri ?? URL(string: "\(resolvedScheme)://account-recovery")!
    }
}
