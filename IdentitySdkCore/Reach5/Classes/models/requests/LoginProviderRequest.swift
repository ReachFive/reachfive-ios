import Foundation

public class LoginProviderRequest: Codable, DictionaryEncodable {
    public let provider: String
    public let providerToken: String?
    public let code: String?
    public let origin: String?
    public let clientId: String
    public let responseType: String
    public let scope: String
    
    public init(provider: String, providerToken: String?, code: String?, origin: String?, clientId: String, responseType: String, scope: String) {
        self.provider = provider
        self.providerToken = providerToken
        self.code = code
        self.origin = origin
        self.clientId = clientId
        self.responseType = responseType
        self.scope = scope
    }
}
