import AuthenticationServices
import Foundation

public class NewPasskeyRequest {
    public let originWebAuthn: String?
    public let origin: String?
    /// The name that will be displayed by the system when presenting the passkey for login
    public let friendlyName: String
    public let presenting: Presentation

    public init(presenting: Presentation, friendlyName: String, originWebAuthn: String? = nil, origin: String? = nil) {
        self.originWebAuthn = originWebAuthn
        self.origin = origin
        self.friendlyName = friendlyName
        self.presenting = presenting
    }
}
