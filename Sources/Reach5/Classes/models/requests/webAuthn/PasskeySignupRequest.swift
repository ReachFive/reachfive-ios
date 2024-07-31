import Foundation
import AuthenticationServices

public class PasskeySignupRequest {
    public let passkeyProfile: ProfilePasskeySignupRequest
    /// The name that will be displayed by the system when presenting the passkey for login
    public let friendlyName: String
    public let originWebAuthn: String?
    public let scopes: [String]?
    public let anchor: ASPresentationAnchor
    public let origin: String?
    
    public init(passkeyProfile: ProfilePasskeySignupRequest, friendlyName: String, anchor: ASPresentationAnchor, originWebAuthn: String? = nil, scopes: [String]? = nil, origin: String? = nil) {
        self.passkeyProfile = passkeyProfile
        self.friendlyName = friendlyName
        self.originWebAuthn = originWebAuthn
        self.scopes = scopes
        self.anchor = anchor
        self.origin = origin
    }
}
