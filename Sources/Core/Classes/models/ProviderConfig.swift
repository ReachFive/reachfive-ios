import Foundation

public class ProviderConfig: Codable {
    public let provider: String
    public let variant: String
    public let clientId: String?
    public let scope: [String]?

    /// The universal link as the backend sends it.
    ///
    /// Held as a string rather than decoded straight into a `URL`, because `URL(string:)` rejects `""` — what
    /// an unset text field in the console yields — and a `Decodable` array is all-or-nothing: one such value
    /// aborted the decoding of the whole `/identity/v1/providers` payload, so `initialize()` failed
    /// permanently and *every* provider was lost, not only the one whose link was wrong.
    private let rawUniversalLink: String?

    private enum CodingKeys: String, CodingKey {
        case provider, variant, clientId, scope
        // The decoder's `.convertFromSnakeCase` turns the payload's `universal_link` into `universalLink`.
        case rawUniversalLink = "universalLink"
    }

    /// The provider's universal link, or `nil` when the configuration carries none that could serve as one: a
    /// host is what an `.https` callback of `ASWebAuthenticationSession` needs, and `URL(string:)` accepts a
    /// value such as `"toto"` as a relative reference that has none.
    ///
    /// The provider itself keeps working — a custom-scheme login needs no universal link — and one in
    /// universal-link mode reports the missing configuration on its own (`DefaultProvider.init` logs it and
    /// defers the failure to `login()`). With `SdkInternalConfig.loggingEnabled`, the rejected value is in the
    /// logged response body.
    public var universalLink: URL? {
        guard let rawUniversalLink, let url = URL(string: rawUniversalLink), url.normalizedHost != nil else {
            return nil
        }
        return url
    }

    public var providerWithVariant: String { provider + ":" + variant }
}
