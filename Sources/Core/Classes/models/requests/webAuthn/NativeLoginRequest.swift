import Foundation
import AuthenticationServices

public class NativeLoginRequest {
    public let originWebAuthn: String?
    public let scopes: [String]?
    public let anchor: ASPresentationAnchor
    public let origin: String?
    
    public init(anchor: ASPresentationAnchor, originWebAuthn: String? = nil, scopes: [String]? = nil, origin: String? = nil) {
        self.originWebAuthn = originWebAuthn
        self.scopes = scopes
        self.anchor = anchor
        self.origin = origin
    }
}
