import Foundation

public class ProviderConfig: Codable {
    public let provider: String
    public let variant: String
    public let clientId: String?
    public let scope: [String]?

    /// Held as a string, not a `URL`: `URL(string:)` rejects `""` and a `Decodable` array is all-or-nothing
    ///  one such value aborted the whole `/identity/v1/providers` payload, losing every provider and leaving `initialize()` in failure.
    private let rawUniversalLink: String?

    private enum CodingKeys: String, CodingKey {
        case provider, variant, clientId, scope
        // `.convertFromSnakeCase` turns the payload's `universal_link` into `universalLink`.
        case rawUniversalLink = "universalLink"
    }

    /// `nil` when the configuration carries no link that could serve as one — a host is what an `.https`
    /// callback of `ASWebAuthenticationSession` needs, and `URL(string:)` reads a value such as `"empty"` as a
    /// relative reference that has none.
    public var universalLink: URL? {
        guard let rawUniversalLink, let url = URL(string: rawUniversalLink), url.normalizedHost != nil else {
            return nil
        }
        return url
    }

    public var providerWithVariant: String { provider + ":" + variant }
}
