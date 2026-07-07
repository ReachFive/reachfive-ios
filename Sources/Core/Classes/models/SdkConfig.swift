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
    ) {
        self.domain = domain
        self.clientId = clientId

        let scheme = customScheme ?? "reachfive-\(clientId)"
        self.customScheme = scheme

        // Built unconditionally so that an invalid scheme is caught at init even when every URI is provided explicitly
        let defaultRedirectUri = Self.defaultUri(scheme: scheme, path: "callback")
        self.redirectUri = redirectUri ?? defaultRedirectUri
        self.mfaUri = mfaUri ?? Self.defaultUri(scheme: scheme, path: "mfa")
        self.emailVerificationUri = emailVerificationUri ?? Self.defaultUri(scheme: scheme, path: "email-verification")
        self.accountRecoveryUri = accountRecoveryUri ?? Self.defaultUri(scheme: scheme, path: "account-recovery")
    }

    /// Validation by construction: `URL(string:)` applies Foundation's RFC 3986 parsing,
    /// the same rules the rest of the system will enforce on every redirect.
    /// Checking the parsed scheme is required because a malformed input can still parse,
    /// just not as intended: with "my:app", "my" becomes the scheme and "app://callback" the path;
    /// with "my/app" the whole string parses as a scheme-less relative reference.
    internal static func makeUri(scheme: String, path: String) -> URL? {
        guard !scheme.isEmpty, // "://callback" parses, with an empty scheme
              let url = URL(string: "\(scheme)://\(path)"),
              url.scheme?.lowercased() == scheme.lowercased()
        else {
            return nil
        }
        return url
    }

    private static func defaultUri(scheme: String, path: String) -> URL {
        guard let url = makeUri(scheme: scheme, path: path) else {
            preconditionFailure("""
                '\(scheme)' is not a valid URL scheme: it must start with a letter and contain only letters, digits, '+', '-' or '.'. \
                If no customScheme is passed, the scheme is derived from the clientId as 'reachfive-<clientId>'. \
                Pass an explicit valid customScheme, and declare it in your app's Info.plist (CFBundleURLSchemes) and in your ReachFive console.
                """)
        }
        return url
    }
}
