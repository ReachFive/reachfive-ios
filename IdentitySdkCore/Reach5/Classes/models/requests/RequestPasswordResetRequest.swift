import Foundation

public class RequestPasswordResetRequest: Codable, DictionaryEncodable {
    public let clientId: String
    public let email: String?
    public let phoneNumber: String?
    public let redirectUrl: String?
    
    public init(clientId: String, email: String?, phoneNumber: String?, redirectUrl: String?) {
        self.clientId = clientId
        self.email = email
        self.phoneNumber = phoneNumber
        self.redirectUrl = redirectUrl
    }
}
