import Foundation

public class SdkConfig {
    /// Your ReachFive domain, not normalized.
    public let domain: String

    /// Like `domain`, but normalized the way RFC 6454 §4, step 5 requires for comparing hosts: lower-cased, with an IPv6
    /// literal's brackets restored (`URL.host` strips them). `domain` itself is kept exactly as given, so
    /// prefer this whenever you compare it against another host
    public var normalizedDomain: String {
        baseUrlComponents.url?.normalizedHost ?? domain.lowercased()
    }

    public let clientId: String

    /// The base of every API URL: scheme and host, validated at init. `ReachFiveApi.createUrl` copies it and
    /// adds a path and query items — a `struct`, so each caller gets its own copy.
    internal let baseUrlComponents: URLComponents

    /// The scheme. Defaults to `reachfive-clientId`, lower-cased — a scheme is case-insensitive (RFC 3986 §3.1)
    public let customScheme: String
    /// The redirect URI for passwordless. Defaults to `reachfive-clientId://callback`
    public let redirectUri: URL
    /// The redirect URI for MFA. Defaults to `reachfive-clientId://mfa`
    public let mfaUri: URL
    /// The redirect URI for Account Recovery. Defaults to `reachfive-clientId://account-recovery`
    public let accountRecoveryUri: URL
    /// The redirect URI for email verification. Defaults to `reachfive-clientId://email-verification`
    public let emailVerificationUri: URL

    /// The WebAuthn origin sent to the server for every passkey request that does not carry its own, as a
    /// serialized origin (`https://host`): scheme, host and non-default port only
    public let originWebAuthn: String

    /// Validates parameters and stops the program with a `preconditionFailure` at the first problem:
    /// - `domain` must be a bare host: no scheme, port, path or trailing slash;
    /// - `customScheme` must be a valid URL scheme (RFC 3986 §3.1);
    /// - `redirectUri`/`mfaUri`/`accountRecoveryUri`/`emailVerificationUri` must carry a scheme plus a host
    ///   or a path; an `http`/`https` one must have a host;
    /// - `originWebAuthn` must be a valid origin (RFC 6454 §6.2: ASCII Serialization of an Origin).
    ///
    /// `originWebAuthn` defaults to `https://<domain>`, which is right unless your passkeys are scoped to a
    /// different relying party, such as a custom domain or one shared across several of your apps.
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
        guard let base = Self.baseComponents(domain: domain) else {
            preconditionFailure("'\(domain)' is not a valid domain: it must be a bare host, with no scheme, port, path or trailing slash, e.g. 'example.reach5.net'.")
        }
        self.baseUrlComponents = base.components
        self.domain = domain
        self.clientId = clientId

        // RFC 3986 §3.1 makes a scheme case-insensitive, but `Foundation.URL` is case sensitive
        // so we lowercase it to avoid problems
        let scheme = (customScheme ?? "reachfive-\(clientId)").lowercased()
        guard Self.isValidScheme(scheme) else {
            preconditionFailure("""
                '\(scheme)' is not a valid URL scheme: it must start with a letter and contain only letters, digits, '+', '-' or '.'. \
                If no customScheme is passed, the scheme is derived from the clientId as 'reachfive-<clientId>'. \
                Pass an explicit valid customScheme, and declare it in your app's Info.plist (CFBundleURLSchemes) and in your ReachFive console.
                """)
        }
        self.customScheme = scheme

        self.redirectUri = Self.checkedUri(redirectUri, scheme, name: "callback")
        self.mfaUri = Self.checkedUri(mfaUri, scheme, name: "mfa")
        self.emailVerificationUri = Self.checkedUri(emailVerificationUri, scheme, name: "email-verification")
        self.accountRecoveryUri = Self.checkedUri(accountRecoveryUri, scheme, name: "account-recovery")

        if let originWebAuthn {
            guard let origin = originWebAuthn.serializedOrigin else {
                preconditionFailure("'\(originWebAuthn)' is not a valid WebAuthn origin: it must be an absolute URL with a scheme and a host, e.g. https://auth.example.com.")
            }
            self.originWebAuthn = origin
        } else {
            self.originWebAuthn = base.origin
        }
    }

    /// Validate the domain by constructing it in a URLComponents.
    /// It returns the serialized origin alongside it for convenience.
    internal static func baseComponents(domain: String) -> (components: URLComponents, origin: String)? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = domain
        guard let origin = components.url?.serializedOrigin else { return nil }
        return (components, origin)
    }

    /// Validation by construction: `URL(string:)` applies Foundation's RFC 3986 parsing.
    internal static func isValidScheme(_ scheme: String) -> Bool {
        // Checked against a throwaway host, just to activate the scheme validation.
        guard !scheme.isEmpty, // "://y" parses, with an empty scheme
              let url = URL(string: "\(scheme)://y")
        else {
            return false
        }
        return url.normalizedScheme == scheme.lowercased()
    }

    /// Whether this URL could ever match an incoming callback, i.e. whether `matchesEndpoint(of:)` can tell
    /// it apart from the SDK's other callback URIs: it needs a scheme, plus a host or a non-empty
    /// normalized path to discriminate on.
    ///
    /// An `http`/`https` URI needs a host: its grammar requires one (RFC 9110 §4.2.1), and the only channel
    /// that can deliver it — an `ASWebAuthenticationSession` built with `callback: .https(host:path:)` — is
    /// given that host explicitly. A host-less `https:///callback` would be accepted here only to fail
    /// later, when `WebAuthenticationSession.prepareSession` throws for the very same reason.
    ///
    /// Any other scheme is a private-use one (RFC 7595 §3.8), so RFC 8252 §7.1 spells its redirect URI
    /// *without* an authority: `com.example.app:/oauth2redirect/example-provider`, a single slash and a
    /// path. Both channels that can deliver it — `ASWebAuthenticationSession`'s `callbackURLScheme:` and
    /// `application(_:open:)` — discriminate on the scheme alone, so a path is enough.
    ///
    /// A URI with neither a host nor a path (`custom:opaque`, `reachfive-abc://`, `com.example.app:/`, whose
    /// path normalizes to `""`) is rejected because it is indistinguishable, under `matchesEndpoint(of:)`,
    /// from every other empty-endpoint URI of its scheme.
    ///
    /// This is a check on the *shape*, not on deliverability: no parsing can tell whether the scheme is
    /// declared in `CFBundleURLSchemes`, whether the host is an Associated Domain, or whether the URI is
    /// whitelisted in the ReachFive console.
    internal static func isValidCallbackUri(_ uri: URL) -> Bool {
        guard uri.normalizedScheme != nil else { return false }
        if uri.isHttpBased { return uri.normalizedHost != nil }
        return uri.normalizedHost != nil || !uri.normalizedPath.isEmpty
    }

    private static func checkedUri(_ uri: URL?, _ scheme: String, name: String) -> URL {
        // The scheme is already validated, and the names are literal, so the force-unwrap cannot fail
        guard let uri else { return URL(string: "\(scheme)://\(name)")! }
        guard Self.isValidCallbackUri(uri) else {
            preconditionFailure("""
                '\(uri)' is not a valid \(name) URI: it needs a scheme, plus a host or a path to tell it apart \
                from the SDK's other callbacks — and an 'http'/'https' URI needs a host, which its grammar \
                requires. Any of these shapes works: '\(scheme)://\(name)', \
                'com.example.app:/oauth2redirect/\(name)' (the RFC 8252 §7.1 form, no authority) or \
                'https://your-app.com/\(name)'. Note that one slash and two are *different* endpoints, so the \
                value must match your ReachFive console entry exactly. \
                Leave the '\(name)' parameter unset to use the default derived from customScheme.
                """)
        }
        return uri
    }
}
