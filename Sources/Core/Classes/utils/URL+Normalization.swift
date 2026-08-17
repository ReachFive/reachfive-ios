import Foundation

/// The two normalizations Foundation does *not* apply, factored out because every consumer needs them and
/// getting one wrong is not a compile error but a silent mismatch: a callback the SDK fails to recognise, or
/// an origin the server rejects.
///
/// RFC 3986 §3.1 and §3.2.2 make the scheme and the host case-insensitive, and §6.2.2.1 asks for the
/// lower-case form when comparing or serializing. `URL` returns both with the case they were written in.
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
    ///   Those build a URL that only fails later, on the network, so they are reported as `nil` here.
    var normalizedHost: String? {
        guard let host, !host.isEmpty else { return nil }
        let lowercased = host.lowercased()
        // An IPv6 literal is the only host that can contain a colon: a registered name cannot, since the
        // colon would have been parsed as the port delimiter.
        return lowercased.contains(":") ? "[\(lowercased)]" : lowercased
    }

    /// This URL reduced to its origin, serialized as RFC 6454 §6.2 (ASCII Serialization of an Origin)
    /// defines it: scheme, host, and the port only when it differs from the scheme's default. `nil` when
    /// there is no scheme or no host to build one from — a URL is not necessarily an origin.
    ///
    /// This is the form WebAuthn requires for `CollectedClientData.origin`, and it is not
    /// `URL.absoluteString`, which would keep the path, the query and the trailing slash an origin has no
    /// room for.
    ///
    /// Reassembled through `URLComponents` rather than by interpolating the parts, because `URL.host`
    /// percent-*decodes*: `https://a%20b.example` reads back as the host `a b.example`, and interpolating
    /// that would emit an origin containing a raw space. `URLComponents` refuses to build a URL from such a
    /// host, which is the answer we want — the nil says "not an origin" just as much as a missing host does.
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

    /// The port RFC 6454 §6.2 step 5 lets an origin leave out. Only the two schemes WebAuthn allows are
    /// listed: anything else keeps whatever port it carries.
    private static func defaultPort(forScheme scheme: String) -> Int? {
        ["http": 80, "https": 443][scheme]
    }
}
