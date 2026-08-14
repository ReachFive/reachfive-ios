import Foundation

/// The one place a WebAuthn origin is validated and serialized, shared by the SDK and by the `#WebAuthnOrigin`
/// macro plugin.
///
/// Sharing it is the point of this target: the macro rejects at compile time exactly what `SdkConfig` would
/// reject at init, because both run this function rather than agreeing by convention. A second copy inside the
/// plugin would be a copy that drifts, and it would drift silently — the whole failure mode this validation
/// exists to prevent.
package enum WebAuthnOrigin {
    /// The serialized origin of `url`, or `nil` when it is not one.
    ///
    /// The WebAuthn spec requires `CollectedClientData.origin` to follow RFC 6454 ("The Web Origin Concept"),
    /// §6.2 ASCII Serialization of an Origin — not the WHATWG HTML/URL origin concept, which is a related but
    /// distinct text. RFC 6454 also requires the host lower-cased (§4.5) and the port omitted when it is the
    /// scheme's default (§6.2.5); `Foundation.URL` does neither on its own.
    package static func serialized(_ url: URL) -> String? {
        // `normalizedScheme`/`normalizedHost` carry the case folding RFC 6454 §4.5 asks for, the brackets an
        // IPv6 literal needs, and the rejection of a host-less authority such as "https://:8443".
        guard let scheme = url.normalizedScheme, let host = url.normalizedHost else { return nil }
        let defaultPort = ["http": 80, "https": 443][scheme]
        guard let port = url.port, port != defaultPort else { return "\(scheme)://\(host)" }
        return "\(scheme)://\(host):\(port)"
    }

    /// Why `literal` is not usable as a WebAuthn origin, or `nil` when it is.
    ///
    /// Only the macro calls this: it needs a reason to put in a diagnostic, where `SdkConfig` only needs a
    /// yes/no. Both answers come from `serialized` above, so the two can't disagree on the verdict itself.
    package static func rejection(of literal: String) -> Rejection? {
        guard let url = URL(string: literal) else {
            return .notAURL
        }
        guard let origin = serialized(url) else {
            return .notAnOrigin
        }
        // An origin is a scheme, a host and a non-default port — nothing else. Anything the round trip drops
        // (a path, a trailing slash, uppercase, a default port) was written but would never be sent, so the
        // literal claims something the SDK does not do. Worth an error rather than a silent trim, since the
        // integrator would otherwise read their own literal back off the console and see a different value.
        guard origin == literal else {
            return .notSerialized(expected: origin)
        }
        return nil
    }

    package enum Rejection: Equatable {
        case notAURL
        case notAnOrigin
        case notSerialized(expected: String)

        package var message: String {
            switch self {
            case .notAURL:
                return "'#WebAuthnOrigin' needs a valid URL"
            case .notAnOrigin:
                return "a WebAuthn origin needs a scheme and a host, e.g. https://auth.example.com"
            case let .notSerialized(expected):
                return "a WebAuthn origin is a scheme, a host and a non-default port only — write '\(expected)'"
            }
        }

        /// The literal to substitute, when the input is fixable by rewriting it.
        package var correction: String? {
            switch self {
            case .notAURL, .notAnOrigin: return nil
            case let .notSerialized(expected): return expected
            }
        }
    }
}
