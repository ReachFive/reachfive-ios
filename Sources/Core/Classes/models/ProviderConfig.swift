import Foundation

public class ProviderConfig: Codable {
    public let provider: String
    public let clientId: String?
    public let universalLink: String?
    public let scope: [String]?
}
