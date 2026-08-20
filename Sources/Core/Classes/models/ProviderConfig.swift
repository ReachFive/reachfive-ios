import Foundation

public class ProviderConfig: Codable {
    public let provider: String
    public let variant: String
    public let clientId: String?
    /// The provider's universal link, when it has a usable one. `nil` when the backend configuration carries
    /// none, or carries one no universal-link session could use — see ``init(from:)``.
    public let universalLink: URL?
    public let scope: [String]?

    public var providerWithVariant: String { provider + ":" + variant }

    /// Hand-written for `universalLink` alone; every other field is decoded exactly as the synthesized
    /// initializer would.
    ///
    /// Decoding it straight into a `URL` made an unusable value a *decoding* failure, and a `Decodable` array
    /// is all-or-nothing: one such value aborted the whole `/identity/v1/providers` payload, so
    /// `initialize()` failed permanently and every provider was lost, not only the one whose link was wrong.
    /// `""` was enough to trigger it — `URL(string:)` rejects it, and that is what an unset text field in the
    /// console yields.
    ///
    /// It is a configuration question rather than a decoding one: the value arrives as a well-formed string
    /// and simply cannot serve as a universal link. So it is read as a string and converted here, and a value
    /// with no host counts as "not configured" — a host is what an `.https` callback of
    /// `ASWebAuthenticationSession` needs, and `URL(string:)` accepts one such as `"toto"` as a relative
    /// reference that has none. The provider keeps working either way: a custom-scheme login needs no
    /// universal link, and one in universal-link mode reports the missing configuration on its own
    /// (`DefaultProvider.init` logs it and defers the failure to `login()`).
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(String.self, forKey: .provider)
        variant = try container.decode(String.self, forKey: .variant)
        clientId = try container.decodeIfPresent(String.self, forKey: .clientId)
        scope = try container.decodeIfPresent([String].self, forKey: .scope)
        universalLink = Self.usableUniversalLink(
            try container.decodeIfPresent(String.self, forKey: .universalLink),
            provider: provider)
    }

    /// `nil` for an absent or empty value — the field is simply unset — and for one with no host, which is
    /// logged since the intent was there and the configuration is wrong.
    private static func usableUniversalLink(_ raw: String?, provider: String) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let url = URL(string: raw), url.normalizedHost != nil else {
            Logger.shared.log("""
                The universal link configured for provider '\(provider)' is unusable and is ignored: \
                '\(raw)' has no host. A universal link is an absolute https URL, e.g. \
                https://example.com/callback. A login in universal-link mode on this provider will fail.
                """)
            return nil
        }
        return url
    }
}
