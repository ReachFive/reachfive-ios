import AuthenticationServices
import Foundation

public class PasskeySignupRequest {
    public let passkeyProfile: ProfilePasskeySignupRequest
    /// The name that will be displayed by the system when presenting the passkey for login
    public let friendlyName: String
    public let originWebAuthn: String?
    public let scopes: [String]?
    public let presenting: Presentation
    public let origin: String?

    public init(passkeyProfile: ProfilePasskeySignupRequest, friendlyName: String, presenting: Presentation, originWebAuthn: String? = nil, scopes: [String]? = nil, origin: String? = nil) {
        self.passkeyProfile = passkeyProfile
        self.friendlyName = friendlyName
        self.originWebAuthn = originWebAuthn
        self.scopes = scopes
        self.presenting = presenting
        self.origin = origin
    }
}
