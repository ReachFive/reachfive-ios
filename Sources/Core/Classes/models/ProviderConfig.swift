import Foundation

public class ProviderConfig: Codable {
    public let provider: String
    public let variant: String
    public let clientId: String?
    /// The provider's universal link, when it has one. `nil` when the backend configuration carries no
    /// usable one — see ``init(from:)`` for what "usable" excludes.
    public let universalLink: URL?
    public let scope: [String]?

    public var providerWithVariant: String { provider + ":" + variant }

    /// Hand-written for `universalLink` alone: decoding it straight into a `URL` makes one unusable value
    /// abort the whole `/identity/v1/providers` payload, taking every other provider's configuration down
    /// with it and leaving `initialize()` in permanent failure. `""` is enough to trigger it — `URL(string:)`
    /// rejects it, and a `Decodable` array is all-or-nothing.
    ///
    /// So the field is read as a string and converted here, and anything a universal-link session could not
    /// use counts as "not configured" rather than as a corrupt payload: the provider that needs it reports it
    /// on its own (`DefaultProvider.init` logs it and defers the failure to `login()`), and the providers
    /// that do not need it keep working.
    ///
    /// "Usable" means a scheme and a host, which is what an `.https` callback of
    /// `ASWebAuthenticationSession(url:callback:completionHandler:)` requires. That rules out `""`, but also
    /// a value such as `"toto"`, which `URL(string:)` happily parses as a relative reference with neither.
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

    /// `nil` for an absent or empty value — the field is simply unset — and for one that cannot serve as a
    /// universal link, which is logged since the intent was there and the configuration is wrong.
    private static func usableUniversalLink(_ raw: String?, provider: String) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let url = URL(string: raw), url.host != nil else {
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
