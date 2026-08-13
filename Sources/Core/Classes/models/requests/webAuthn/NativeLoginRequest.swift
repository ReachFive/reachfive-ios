import AuthenticationServices
import Foundation

public class NativeLoginRequest {
    public let originWebAuthn: String?
    public let scopes: [String]?
    public let presenting: Presentation
    public let origin: String?

    public init(presenting: Presentation, originWebAuthn: String? = nil, scopes: [String]? = nil, origin: String? = nil) {
        self.originWebAuthn = originWebAuthn
        self.scopes = scopes
        self.presenting = presenting
        self.origin = origin
    }
}

struct ResolvedNativeLoginRequest {
    let presenting: Presentation
    let originWebAuthn: String
    /// The requested scopes, or the SDK's own when none were requested.
    let scopes: [String]
    /// The ReachFive analytics origin, optional by nature.
    let origin: String?
}
