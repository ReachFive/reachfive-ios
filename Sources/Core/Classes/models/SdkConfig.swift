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

    /// The WebAuthn origin sent to the server for passkey requests, as a serialized origin
    /// (`https://host`). Set it once here instead of repeating it on every passkey request.
    ///
    /// Defaults to `https://<domain>`, which is right unless your passkeys are scoped to a different
    /// relying party — a custom domain, or one shared across several of your apps. A request that carries
    /// its own `originWebAuthn` still wins over this value.
    public let originWebAuthn: URL?

    public init(
        domain: String,
        clientId: String,
        customScheme: String? = nil,
        redirectUri: URL? = nil,
        mfaUri: URL? = nil,
        accountRecoveryUri: URL? = nil,
        emailVerificationUri: URL? = nil,
        originWebAuthn: URL? = nil
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

        if let originWebAuthn, Self.serializedOrigin(originWebAuthn) == nil {
            preconditionFailure("""
                '\(originWebAuthn)' is not a valid WebAuthn origin: it must be an absolute URL with a \
                scheme and a host, e.g. https://auth.example.com.
                """)
        }
        self.originWebAuthn = originWebAuthn
    }

    /// The WebAuthn origin to use when a request does not carry its own, serialized the way the server and
    /// the system expect it: scheme, host and non-default port only. Neither a path nor a trailing slash
    /// belongs in an origin, and `URL.absoluteString` would keep both.
    ///
    /// Only this configured value is normalized: the per-request `originWebAuthn` overrides are `String`s
    /// and are sent as given.
    var webAuthnOrigin: String {
        guard let originWebAuthn, let origin = Self.serializedOrigin(originWebAuthn) else {
            return "https://\(domain)"
        }
        return origin
    }

    /// `internal`, like `makeUri` below: the single construction point on which the init's precondition
    /// relies, so tests can probe acceptable/unacceptable inputs without triggering it.
    ///
    /// Mirrors the WHATWG "serialization of an origin" (https://html.spec.whatwg.org/multipage/browsers.html#origin)
    /// applied to `Foundation.URL`, which parses URLs but does not itself normalize them to the WHATWG URL
    /// Standard: hence lower-casing the host here (WHATWG's domain/IPv6 parsers lower-case as they go) and
    /// dropping the port when it is the scheme's default (the WHATWG URL parser nulls it at parse time,
    /// `URL.port` does not).
    internal static func serializedOrigin(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let rawHost = url.host else { return nil }
        // URL.host returns an IPv6 literal unbracketed ("::1"); an origin needs it back in brackets.
        let host = (rawHost.contains(":") ? "[\(rawHost)]" : rawHost).lowercased()
        let defaultPort = ["http": 80, "https": 443][scheme]
        guard let port = url.port, port != defaultPort else { return "\(scheme)://\(host)" }
        return "\(scheme)://\(host):\(port)"
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
