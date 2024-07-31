import Foundation

public class Consent: Codable, DictionaryEncodable {
    public let granted: Bool
    public let consentType: String?
    public let date: String
    
    public init(
        granted: Bool,
        consentType: String?,
        date: String
    ) {
        self.granted = granted
        self.consentType = consentType
        self.date = date
    }
}
