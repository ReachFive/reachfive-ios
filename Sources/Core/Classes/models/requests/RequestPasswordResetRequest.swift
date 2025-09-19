import Foundation

public class RequestPasswordResetRequest: Codable, DictionaryEncodable {
    public let clientId: String
    public let email: String?
    public let phoneNumber: String?
    public let redirectUrl: String?
    public let origin: String?
    
    public init(clientId: String, email: String?, phoneNumber: String?, redirectUrl: String?, origin: String? = nil) {
        self.clientId = clientId
        self.email = email
        self.phoneNumber = phoneNumber
        self.redirectUrl = redirectUrl
        self.origin = origin
    }
}
