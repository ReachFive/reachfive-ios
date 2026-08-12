import AuthenticationServices
import Foundation

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

struct ResolvedNativeLoginRequest {
    let anchor: ASPresentationAnchor
    let originWebAuthn: String
    /// The requested scopes, or the SDK's own when none were requested.
    let scopes: [String]
    /// The ReachFive analytics origin, optional by nature.
    let origin: String?
}
