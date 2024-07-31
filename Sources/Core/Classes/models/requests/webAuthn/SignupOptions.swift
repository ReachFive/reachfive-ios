import Foundation

public class SignupOptions: Codable, DictionaryEncodable {
    public let origin: String
    public let friendlyName: String
    public let profile: ProfilePasskeySignupRequest
    public let clientId: String?
    public let scope: String
    
    public init(origin: String, friendlyName: String, profile: ProfilePasskeySignupRequest, clientId: String?, scope: [String]) {
        self.origin = origin
        self.friendlyName = friendlyName
        self.profile = profile
        self.clientId = clientId
        self.scope = scope.joined(separator: " ")
    }
}
