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

    /// The WebAuthn origin sent to the server for every passkey request that does not carry its own, as a
    /// serialized origin (`https://host`): scheme, host and non-default port only, since neither a path nor
    /// a trailing slash belongs in an origin.
    ///
    /// It is the `originWebAuthn` passed at init, or `https://<domain>` when none was — the latter being
    /// right unless your passkeys are scoped to a different relying party, such as a custom domain or one
    /// shared across several of your apps. Resolved once here, so this always holds the value the SDK will
    /// actually send, never the raw input.
    ///
    /// Both paths go through `serializedOrigin`, so they cannot disagree on a host that needs normalizing:
    /// both fold the case (RFC 6454 §4.5) and both send the host in the A-label form §6.2 ASCII
    /// Serialization expects (§4, step 5 note). Returning `café.example` verbatim would be the §6.1
    /// *Unicode* serialization, a different algorithm, and not the one `CollectedClientData.origin` is
    /// specified against.
    public let webAuthnOrigin: String

    /// The origin a passkey request must carry: the one the request sets, or `webAuthnOrigin` when it sets
    /// none. An override is normalized through the very same `serializedOrigin`, so a per-request value and
    /// the configured one can never send two spellings of the same host.
    ///
    /// It throws rather than stopping the program, unlike the two `preconditionFailure`s in `init`: a
    /// configuration is written once and checked at launch, where a crash is a fast, unmissable signal,
    /// whereas this is runtime data reaching a call that already is `async throws` — and an integrator can
    /// act on an error there.
    public func webAuthnOrigin(overriddenBy override: String? = nil) throws -> String {
        guard let override else { return webAuthnOrigin }
        guard let origin = URL(string: override)?.serializedOrigin else {
            throw ReachFiveError.TechnicalError(reason: """
                '\(override)' is not a valid WebAuthn origin: it must be an absolute URL with a scheme and \
                a host, e.g. https://auth.example.com. Leave the request's originWebAuthn unset to use the \
                one configured on SdkConfig.
                """)
        }
        return origin
    }

    /// Validates everything eagerly and stops the program with a `preconditionFailure` at the first
    /// problem, rather than letting a bad value reach a network call later — crashing at launch is a fast,
    /// unmissable signal, and the message names the offending parameter and its fix.
    ///
    /// Three independent checks, in this order: `domain` must be a bare host (see `domain`); the scheme —
    /// `customScheme`, or the one derived from `clientId` when it is `nil` — must be a valid URL scheme; and
    /// `originWebAuthn`, if provided, must be a valid origin. The scheme check always runs, even when every
    /// `redirectUri`/`mfaUri`/`accountRecoveryUri`/`emailVerificationUri` is passed explicitly — each is then
    /// kept exactly as given, but building the discarded default is what catches an invalid scheme early
    /// rather than only on whichever URI is left to derive from it.
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
            preconditionFailure("""
                '\(domain)' is not a valid domain: it must be a bare host, with no scheme, port, path or \
                trailing slash, e.g. example.reach5.net. \
                It is the domain of your ReachFive account, as shown in your ReachFive console, and the SDK \
                builds every API request on it. \
                Pass only the host, dropping any 'https://' prefix and any trailing '/'.
                """)
        }
        self.baseUrlComponents = base.components
        self.domain = domain
        self.clientId = clientId

        let scheme = customScheme ?? "reachfive-\(clientId)"
        self.customScheme = scheme

        let defaultRedirectUri = Self.defaultUri(scheme: scheme, host: "callback")
        self.redirectUri = redirectUri ?? defaultRedirectUri
        self.mfaUri = mfaUri ?? Self.defaultUri(scheme: scheme, host: "mfa")
        self.emailVerificationUri = emailVerificationUri ?? Self.defaultUri(scheme: scheme, host: "email-verification")
        self.accountRecoveryUri = accountRecoveryUri ?? Self.defaultUri(scheme: scheme, host: "account-recovery")

        if let originWebAuthn {
            guard let origin = originWebAuthn.serializedOrigin else {
                preconditionFailure("""
                    '\(originWebAuthn)' is not a valid WebAuthn origin: it must be an absolute URL with a \
                    scheme and a host, e.g. https://auth.example.com.
                    """)
            }
            self.webAuthnOrigin = origin
        } else {
            // `domain` is validated at init but kept as given, so it can still carry the mixed case DNS
            // tolerates — or non-ASCII labels. The fallback is the origin `baseComponents` already
            // serialized, from the very components every API request is built on, so the two can never
            // drift apart.
            self.webAuthnOrigin = base.origin
        }
    }

    /// `internal`, like `makeUri` below: the single construction point on
    /// which the init's precondition relies, so tests can probe acceptable/unacceptable inputs without
    /// triggering it.
    ///
    /// Validation by construction, against the exact use the SDK makes of the value: it returns the very
    /// components `ReachFiveApi.createUrl` will build every request on, so validating and using are the same
    /// object rather than two places agreeing by convention.
    ///
    /// It returns the serialized origin alongside them for the same reason: validating a domain and
    /// normalizing it are one step, not two. A domain accepted here has an origin by construction, so no
    /// caller has to force-unwrap one back out of the components, and no invariant has to be argued for in a
    /// comment.
    ///
    /// The check goes through `serializedOrigin`, which reads the host back off the built URL — via
    /// `normalizedHost`, reporting a host-less authority as `nil` — instead of trusting the assignment,
    /// because `URLComponents` accepts two host-less spellings that would otherwise only fail on the network,
    /// in the same channel as a transient failure: the empty string (`https:///path`) and `[]`, an empty IPv6
    /// literal building `https://[]`.
    ///
    /// Foundation still accepts hosts that are well-formed but resolve to nothing (`my_host.example`,
    /// `x..example`); those fail at DNS with an error naming the host, and no parsing can tell a dead domain
    /// from a live one anyway.
    internal static func baseComponents(domain: String) -> (components: URLComponents, origin: String)? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = domain
        guard let origin = components.url?.serializedOrigin else { return nil }
        return (components, origin)
    }

    /// Validation by construction: `URL(string:)` applies Foundation's RFC 3986 parsing,
    /// the same rules the rest of the system will enforce on every redirect.
    /// Checking the parsed scheme is required because a malformed input can still parse,
    /// just not as intended: with "my:app", "my" becomes the scheme and "app://callback" the path;
    /// with "my/app" the whole string parses as a scheme-less relative reference.
    ///
    /// The host is read back for the same reason, and interpolation makes it the likelier of the two to
    /// slip: a `/`, `?`, `#` or `@` inside it silently moves part of the value into the path, the query, the
    /// fragment or the userinfo — `a@b` builds the host `b` — and an empty one builds a host-less URI, the
    /// same malformation `baseComponents` rejects above. Comparing against `normalizedHost` also refuses a
    /// host Foundation had to rewrite to accept it: percent-encoding, which `URL.host` decodes back to a raw
    /// space, or a non-ASCII label it punycodes.
    internal static func makeUri(scheme: String, host: String) -> URL? {
        guard !scheme.isEmpty, // "://callback" parses, with an empty scheme
              let url = URL(string: "\(scheme)://\(host)"),
              url.normalizedScheme == scheme.lowercased(),
              url.normalizedHost == host.lowercased()
        else {
            return nil
        }
        return url
    }

    private static func defaultUri(scheme: String, host: String) -> URL {
        guard let url = makeUri(scheme: scheme, host: host) else {
            preconditionFailure("""
                '\(scheme)' is not a valid URL scheme: it must start with a letter and contain only letters, digits, '+', '-' or '.'. \
                If no customScheme is passed, the scheme is derived from the clientId as 'reachfive-<clientId>'. \
                Pass an explicit valid customScheme, and declare it in your app's Info.plist (CFBundleURLSchemes) and in your ReachFive console.
                """)
        }
        return url
    }
}
