import Foundation

public class VerifyPhoneNumberRequest: Codable, DictionaryEncodable {
    public let phoneNumber: String
    public let verificationCode: String
    
    public init(phoneNumber: String, verificationCode: String) {
        self.phoneNumber = phoneNumber
        self.verificationCode = verificationCode
    }
}
