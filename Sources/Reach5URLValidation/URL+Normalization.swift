import Foundation

/// The two normalizations Foundation does *not* apply, factored out because every consumer needs them and
/// getting one wrong is not a compile error but a silent mismatch: a callback the SDK fails to recognise, or
/// an origin the server rejects.
///
/// RFC 3986 §3.1 and §3.2.2 make the scheme and the host case-insensitive, and §6.2.2.1 asks for the
/// lower-case form when comparing or serializing. `URL` returns both with the case they were written in.
/// `package`, not `public`: the macro plugin and the SDK both need these, but extending `URL` in the
/// public API of an SDK would impose two members on every consumer's `URL`.
extension URL {
    /// The scheme, lower-cased, or `nil` when the URL carries none.
    ///
    /// Comparing a scheme without folding its case has already cost a bug: `loadLoginWebview` never
    /// recognised its own callback whenever the custom scheme held an uppercase letter — which is the
    /// default, since it is derived from the clientId.
    package var normalizedScheme: String? {
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
    package var normalizedHost: String? {
        guard let host, !host.isEmpty else { return nil }
        let lowercased = host.lowercased()
        // An IPv6 literal is the only host that can contain a colon: a registered name cannot, since the
        // colon would have been parsed as the port delimiter.
        return lowercased.contains(":") ? "[\(lowercased)]" : lowercased
    }
}
