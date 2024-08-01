import Foundation

public class SignupRequest: Codable, DictionaryEncodable {
    public let clientId: String
    public let data: ProfileSignupRequest
    public let scope: String
    public let redirectUrl: String?
    public let origin: String?
    
    public init(clientId: String, data: ProfileSignupRequest, scope: String, redirectUrl: String?, origin: String? = nil) {
        self.clientId = clientId
        self.data = data
        self.scope = scope
        self.redirectUrl = redirectUrl
        self.origin = origin
    }
}
