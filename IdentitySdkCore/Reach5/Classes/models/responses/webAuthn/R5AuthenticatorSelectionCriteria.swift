import Foundation

public class R5AuthenticatorSelectionCriteria: Codable, DictionaryEncodable {
    public var authenticatorAttachment: String?
    public var requireResidentKey: Bool?
    public var residentKey: String?
    public var userVerification: String?
    
    public init(authenticatorAttachment: String?, requireResidentKey: Bool?, residentKey: String?, userVerification: String?) {
        self.authenticatorAttachment = authenticatorAttachment
        self.residentKey = residentKey
        self.requireResidentKey = requireResidentKey
        self.userVerification = userVerification
    }
}
