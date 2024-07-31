import Foundation
import AuthenticationServices

public class ResetPasskeyRequest {
    public let email: String?
    public let phoneNumber: String?
    public let verificationCode: String
    
    public let originWebAuthn: String?
    public let origin: String?
    /// The name that will be displayed by the system when presenting the passkey for login
    public let friendlyName: String
    public let anchor: ASPresentationAnchor
    
    public init(verificationCode: String, friendlyName: String, anchor: ASPresentationAnchor, email: String? = nil, phoneNumber: String? = nil, originWebAuthn: String? = nil, origin: String? = nil) {
        self.email = email
        self.phoneNumber = phoneNumber
        self.verificationCode = verificationCode
        self.originWebAuthn = originWebAuthn
        self.origin = origin
        self.friendlyName = friendlyName
        self.anchor = anchor
    }
}

public class AccountRecoveryResponse {
    public let email: String
    public let verificationCode: String
    
    public init(email: String, verificationCode: String) {
        self.email = email
        self.verificationCode = verificationCode
    }
}