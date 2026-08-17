import Foundation

public class SdkConfig {
    /// Your ReachFive domain, as a bare host: `example.reach5.net`. No scheme, port, path or trailing
    /// slash — every API request is built on it. Kept exactly as given, never normalized.
    public let domain: String

    /// `domain`, normalized the way RFC 6454 §4.5 requires for comparing hosts: lower-cased, with an IPv6
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
    /// problem, rather than letting a bad value reach a network call later.
    ///
    /// - `domain` must be a bare host (see `domain`);
    /// - `customScheme` must be a valid URL scheme (RFC 3986 §3.1);
    /// - `redirectUri`/`mfaUri`/`accountRecoveryUri`/`emailVerificationUri` must have both a scheme and a host;
    /// - `originWebAuthn` must be a valid origin.
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

        // Checked once above, not once per URI: a scheme that round-trips for one host round-trips for any
        // of them, so building each of these four from a fixed, safe literal host can never fail once the
        // scheme itself is proven valid.
        self.redirectUri = Self.checkedUri(redirectUri, named: "redirectUri", orDefault: URL(string: "\(scheme)://callback")!)
        self.mfaUri = Self.checkedUri(mfaUri, named: "mfaUri", orDefault: URL(string: "\(scheme)://mfa")!)
        self.emailVerificationUri = Self.checkedUri(emailVerificationUri, named: "emailVerificationUri", orDefault: URL(string: "\(scheme)://email-verification")!)
        self.accountRecoveryUri = Self.checkedUri(accountRecoveryUri, named: "accountRecoveryUri", orDefault: URL(string: "\(scheme)://account-recovery")!)

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

    /// `internal`, like `isValidScheme` below: the single construction point on
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

    /// Validation by construction: `URL(string:)` applies Foundation's RFC 3986 parsing, the same rules the
    /// rest of the system will enforce on every redirect. Checking the parsed scheme is required because a
    /// malformed input can still parse, just not as intended: with "my:app", "my" becomes the scheme and
    /// "app://callback" the path; with "my/app" the whole string parses as a scheme-less relative reference.
    ///
    /// `internal`, like `baseComponents` above, so tests can probe acceptable/unacceptable schemes without
    /// triggering the `preconditionFailure` in `init`. Checked against a throwaway host purely to exercise
    /// the round-trip: unlike `domain`/`originWebAuthn`, nothing here ever interpolates a host that isn't
    /// one of `init`'s four fixed, safe literals ("callback", "mfa", …), so there is nothing to validate on
    /// that side.
    internal static func isValidScheme(_ scheme: String) -> Bool {
        guard !scheme.isEmpty, // "://x" parses, with an empty scheme
              let url = URL(string: "\(scheme)://y")
        else {
            return false
        }
        return url.normalizedScheme == scheme.lowercased()
    }

    /// Whether this URL could ever match an incoming callback: it must have both a scheme and a host, the
    /// two ``URL/matchesEndpoint(of:)`` compares (through `normalizedScheme`/`normalizedHost`, so the same
    /// case-folding rules apply here). `internal`, like `isValidScheme` above, so tests can probe
    /// acceptable/unacceptable values without triggering the `preconditionFailure` in `checkedUri` below.
    internal static func isValidCallbackUri(_ uri: URL) -> Bool {
        uri.normalizedScheme != nil && uri.normalizedHost != nil
    }

    /// `redirectUri`/`mfaUri`/`accountRecoveryUri`/`emailVerificationUri` all go through this: kept exactly
    /// as given when explicit, since — unlike the derived defaults — they may legitimately use a scheme and
    /// host that have nothing to do with `customScheme` (a universal link redirect, for instance). Left
    /// unchecked, a scheme-less or host-less value would still be accepted, and the flow that relies on it
    /// would then fail silently the first time an incoming callback is compared against it, deep inside
    /// ``ReachFive/interceptUrl(_:)`` — in a way that never points back at `SdkConfig`.
    private static func checkedUri(_ uri: URL?, named parameterName: String, orDefault fallback: URL) -> URL {
        guard let uri else { return fallback }
        guard isValidCallbackUri(uri) else {
            preconditionFailure("""
                '\(uri)' is not a valid \(parameterName): it must have both a scheme and a host, e.g. \
                'reachfive-clientId://callback' or 'https://your-app.com/callback'. \
                Leave '\(parameterName)' unset to use the default derived from customScheme.
                """)
        }
        return uri
    }
}
