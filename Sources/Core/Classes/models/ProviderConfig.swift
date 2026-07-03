import Foundation

public class ProviderConfig: Codable {
    public let provider: String
    public let variant: String
    public let clientId: String?
    public let universalLink: URL?
    public let scope: [String]?
    
    public var providerWithVariant: String { provider + ":" + variant }
}
