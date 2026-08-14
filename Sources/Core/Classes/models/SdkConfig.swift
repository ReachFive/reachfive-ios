import Foundation

public class SdkConfig {
    /// Your ReachFive domain, as a bare host: `example.reach5.net`. No scheme, port, path or trailing
    /// slash — every API request is built on it. Kept exactly as given, never normalized.
    public let domain: String
    public let clientId: String

    /// The base of every API URL: scheme and host, validated at init. `ReachFiveApi.createUrl` copies it and
    /// adds a path and query items — a `struct`, so each caller gets its own copy.
    internal let baseUrlComponents: URLComponents

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
        guard let baseUrlComponents = Self.baseUrlComponents(domain: domain) else {
            preconditionFailure("""
                '\(domain)' is not a valid domain: it must be a bare host, with no scheme, port, path or \
                trailing slash, e.g. example.reach5.net. \
                It is the domain of your ReachFive account, as shown in your ReachFive console, and the SDK \
                builds every API request on it. \
                Pass only the host, dropping any 'https://' prefix and any trailing '/'.
                """)
        }
        self.baseUrlComponents = baseUrlComponents
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
        if let originWebAuthn, let origin = Self.serializedOrigin(originWebAuthn) {
            return origin
        }
        // `domain` is validated at init but kept as given, so it can still carry the mixed case DNS tolerates
        // — or non-ASCII labels. Serializing it through `serializedOrigin`, from the very components every API
        // request is built on, is what keeps this path and the configured one from disagreeing: both then fold
        // the case (RFC 6454 §4.5) and both send the host in the A-label form §6.2 ASCII Serialization expects
        // (§4, step 5 note). Returning `café.example` verbatim would be the §6.1 *Unicode* serialization, a
        // different algorithm, and not the one `CollectedClientData.origin` is specified against.
        //
        // Both force-unwraps hold by construction, and are the same guarantee `ReachFiveApi.createUrl` relies
        // on: `baseUrlComponents` exists only because `baseUrlComponents(domain:)` built a URL from it and
        // read a non-empty host back off it — precisely what `serializedOrigin` needs to return a value.
        return Self.serializedOrigin(baseUrlComponents.url!)!
    }

    /// `internal`, like `makeUri` below: the single construction point on which the init's precondition
    /// relies, so tests can probe acceptable/unacceptable inputs without triggering it.
    ///
    /// The WebAuthn spec requires `CollectedClientData.origin` to follow RFC 6454 ("The Web Origin
    /// Concept"), §6.2 ASCII Serialization of an Origin — not the WHATWG HTML/URL origin concept, which is
    /// a related but distinct text. RFC 6454 also requires the host lower-cased (§4.5) and the port
    /// omitted when it is the scheme's default (§6.2.5); `Foundation.URL` does neither on its own.
    internal static func serializedOrigin(_ url: URL) -> String? {
        // `URL.host` is "", not nil, when the authority carries no host at all, as in "https://:8443":
        // an origin needs a host, so reject it rather than serialize "https://:8443".
        guard let scheme = url.scheme?.lowercased(), let rawHost = url.host, !rawHost.isEmpty else { return nil }
        // URL.host returns an IPv6 literal unbracketed ("::1"); an origin needs it back in brackets.
        let host = (rawHost.contains(":") ? "[\(rawHost)]" : rawHost).lowercased()
        let defaultPort = ["http": 80, "https": 443][scheme]
        guard let port = url.port, port != defaultPort else { return "\(scheme)://\(host)" }
        return "\(scheme)://\(host):\(port)"
    }

    /// `internal`, like `serializedOrigin` above and `makeUri` below: the single construction point on
    /// which the init's precondition relies, so tests can probe acceptable/unacceptable inputs without
    /// triggering it.
    ///
    /// Validation by construction, against the exact use the SDK makes of the value: it returns the very
    /// components `ReachFiveApi.createUrl` will build every request on, so validating and using are the same
    /// object rather than two places agreeing by convention.
    ///
    /// The check reads the host back off the built URL instead of trusting the assignment, because
    /// `URLComponents` accepts two host-less spellings that would otherwise only fail on the network, in the
    /// same channel as a transient failure: the empty string (`https:///path`) and `[]`, an empty IPv6
    /// literal, which builds `https://[]` and parses back with an empty host.
    ///
    /// Foundation still accepts hosts that are well-formed but resolve to nothing (`my_host.example`,
    /// `x..example`); those fail at DNS with an error naming the host, and no parsing can tell a dead domain
    /// from a live one anyway.
    internal static func baseUrlComponents(domain: String) -> URLComponents? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = domain
        guard let url = components.url, let host = url.host, !host.isEmpty else { return nil }
        return components
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
