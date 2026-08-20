import Foundation

/// The normalizations Foundation does not apply
///
/// RFC 3986 §3.1 and §3.2.2 make the scheme and the host case-insensitive;
/// §6.2.2.1 asks for the lower-case form when comparing or serializing;
/// and §6.2.3 adds a scheme-based normalization: an empty path is equivalent to a path of `/`
extension URL {
    /// The scheme, lower-cased, or `nil` when the URL carries none.
    var normalizedScheme: String? {
        scheme?.lowercased()
    }

    /// The host in the form a comparison or an origin needs, or `nil` when the authority carries none.
    ///
    /// Two things Foundation leaves to the caller:
    /// - the case, as above;
    /// - the brackets around an IPv6 literal, which `URL.host` strips (`https://[::1]` reads back as `::1`)
    ///   although both an origin and a URL require them.
    ///
    /// A third is folded in without relying on a specific answer: for an authority with a port but no host
    /// (`https://:8443`) or an empty IPv6 literal (`https://[]`), `URL.host` reads `""` almost everywhere
    /// but not on every OS version tested — see `URLNormalizationTests`. The guard below treats an empty
    /// host and a missing one the same way, so it doesn't matter which this particular runtime returns.
    var normalizedHost: String? {
        guard let host, !host.isEmpty else { return nil }
        let lowercased = host.lowercased()
        // An IPv6 literal is the only host that can contain a colon: a registered name cannot, since the
        // colon would have been parsed as the port delimiter.
        return lowercased.contains(":") ? "[\(lowercased)]" : lowercased
    }

    /// The path in the form a callback comparison needs: `"/"` folded onto `""`, the scheme-based
    /// normalization of RFC 3986 §6.2.3 ("an empty path is equivalent to a path of `/`") applied the other
    /// way around.
    ///
    /// A browser routinely appends the trailing slash to an authority-only URL, so a callback declared as
    /// `reachfive-<clientId>://callback` can be delivered back as `reachfive-<clientId>://callback/`.
    /// `URL.path` already drops a trailing slash from a longer path (`…:/cb/` reads back as `/cb`), so `"/"`
    /// is the only case left to fold — and it percent-*decodes* the path, so `…:/a%2Fb` and `…:/a/b` read
    /// back identically too.
    var normalizedPath: String {
        path == "/" ? "" : path
    }

    /// Whether this URL could match an incoming callback: a scheme, plus a host (required for `http`/`https`,
    /// per RFC 9110 §4.2.1) or a `/`-rooted path (RFC 8252 §7.1, e.g. `com.example.app:/oauth2redirect`).
    ///
    /// The leading slash rather than a non-empty path, because Foundation reads a scheme-only URI's path
    /// differently per platform — see `URLNormalizationTests`.
    ///
    /// A check on shape, not on deliverability: nothing here about `CFBundleURLSchemes`, Associated Domains
    /// or the console's whitelist.
    var isValidCallbackUri: Bool {
        guard let normalizedScheme else { return false }
        if Self.schemesRequiringAHost.contains(normalizedScheme) { return normalizedHost != nil }
        return normalizedHost != nil || normalizedPath.hasPrefix("/")
    }

    /// This URL reduced to its origin, serialized as RFC 6454 §6.2 (ASCII Serialization of an Origin)
    /// defines it: scheme, host, and the port only when it differs from the scheme's default. `nil` when
    /// there is no scheme or no host — a URL is not necessarily an origin.
    ///
    /// This is the form WebAuthn requires for `CollectedClientData.origin`, and it is not
    /// `URL.absoluteString`, which would keep the path, the query and the trailing slash
    var serializedOrigin: String? {
        guard let scheme = normalizedScheme, let host = normalizedHost else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if let port, port != Self.defaultPorts[scheme] {
            components.port = port
        }
        return components.url?.absoluteString
    }

    /// The schemes whose grammar makes the authority mandatory (RFC 9110 §4.2.1), so one of them without a
    /// host is malformed rather than unusual.
    ///
    /// Holding the same two schemes as `defaultPorts` below is an accident of what this SDK needs, not a
    /// rule — for example, `ws`/`wss` would require an authority too (RFC 6455 §3). Either list can grow without the other.
    private static let schemesRequiringAHost: Set<String> = ["http", "https"]

    /// The port each scheme leaves implicit, which a serialized origin must therefore leave out (RFC 6454
    /// §6.2 step 5). Only the schemes WebAuthn allows; any other keeps whatever port it carries.
    private static let defaultPorts = ["http": 80, "https": 443]
}
