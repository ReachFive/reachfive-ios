import Foundation

public class UpdatePhoneNumberRequest: Codable, DictionaryEncodable {
    public let phoneNumber: String
    
    public init(phoneNumber: String) {
        self.phoneNumber = phoneNumber
    }
}
