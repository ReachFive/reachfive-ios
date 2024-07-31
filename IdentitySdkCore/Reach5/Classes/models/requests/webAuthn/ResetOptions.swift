import Foundation

public class ResetOptions: Codable, DictionaryEncodable {
    public let email: String?
    public let phoneNumber: String?
    public let verificationCode: String
    public let friendlyName: String
    public let origin: String
    public let clientId: String
    
    public init(email: String?, phoneNumber: String?, verificationCode: String, friendlyName: String, origin: String, clientId: String) {
        self.email = email
        self.phoneNumber = phoneNumber
        self.verificationCode = verificationCode
        self.friendlyName = friendlyName
        self.origin = origin
        self.clientId = clientId
    }
}
