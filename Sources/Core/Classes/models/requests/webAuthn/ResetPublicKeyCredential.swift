import Foundation

public class ResetPublicKeyCredential: Codable, DictionaryEncodable {
    public let email: String?
    public let phoneNumber: String?
    public let verificationCode: String
    public let clientId: String
    public var publicKeyCredential: RegistrationPublicKeyCredential
    
    public init(email: String?, phoneNumber: String?, verificationCode: String, clientId: String, publicKeyCredential: RegistrationPublicKeyCredential) {
        self.email = email
        self.phoneNumber = phoneNumber
        self.verificationCode = verificationCode
        self.clientId = clientId
        self.publicKeyCredential = publicKeyCredential
    }
    
    public init(resetOptions: ResetOptions, publicKeyCredential: RegistrationPublicKeyCredential) {
        self.email = resetOptions.email
        self.phoneNumber = resetOptions.phoneNumber
        self.verificationCode = resetOptions.verificationCode
        self.clientId = resetOptions.clientId
        self.publicKeyCredential = publicKeyCredential
    }
    
}