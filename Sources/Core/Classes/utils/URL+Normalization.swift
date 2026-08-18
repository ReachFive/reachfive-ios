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
    /// Three things Foundation leaves to the caller:
    /// - the case, as above;
    /// - the brackets around an IPv6 literal, which `URL.host` strips (`https://[::1]` reads back as `::1`)
    ///   although both an origin and a URL require them;
    /// - the difference between "no host" and an empty one — `URL.host` is `""`, not `nil`, when the
    ///   authority has a port but no host (`https://:8443`) or an empty IPv6 literal (`https://[]`).
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

    /// `true` when this URL uses `http` or `https`, as opposed to a private-use scheme (RFC 7595 §3.8) — the
    /// distinction `SdkConfig.isValidCallbackUri` needs to decide whether a host is required.
    ///
    /// An exact match on the normalized scheme, never a prefix: `httpx-app://callback` is a perfectly valid
    /// private-use scheme.
    var isHttpBased: Bool {
        guard let normalizedScheme else { return false }
        return Self.defaultPorts.keys.contains(normalizedScheme)
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
        if let port, port != Self.defaultPort(forScheme: scheme) {
            components.port = port
        }
        return components.url?.absoluteString
    }

    /// The default port of each scheme whose authority is part of its grammar. Only the two schemes WebAuthn
    /// allows are listed (RFC 6454 §6.2 step 5 lets an origin leave a default port out); anything else keeps
    /// whatever port it carries.
    private static let defaultPorts = ["http": 80, "https": 443]

    private static func defaultPort(forScheme scheme: String) -> Int? {
        defaultPorts[scheme]
    }
}
