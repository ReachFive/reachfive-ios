import Foundation

public class RequestAccountRecoveryRequest: Codable, DictionaryEncodable {
    public let clientId: String
    public let email: String?
    public let phoneNumber: String?
    public let redirectUrl: String?
    public let origin: String?
    
    public init(clientId: String, email: String? = nil, phoneNumber: String? = nil, redirectUrl: String? = nil, origin: String? = nil) {
        self.clientId = clientId
        self.email = email
        self.phoneNumber = phoneNumber
        self.redirectUrl = redirectUrl
        self.origin = origin
    }
}