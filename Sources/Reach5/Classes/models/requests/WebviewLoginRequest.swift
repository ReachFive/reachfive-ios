import Foundation
import AuthenticationServices

public class WebviewLoginRequest {
    public let state: String
    public let nonce: String
    public let scope: [String]?
    public let presentationContextProvider: ASWebAuthenticationPresentationContextProviding
    public let origin: String?
    public let provider: String?
    
    public init(state: String? = nil, nonce: String? = nil, scope: [String]? = nil, presentationContextProvider: ASWebAuthenticationPresentationContextProviding, origin: String? = nil, provider: String? = nil) {
        self.state = state ?? "state"
        self.nonce = nonce ?? "nonce"
        self.scope = scope
        self.presentationContextProvider = presentationContextProvider
        self.origin = origin
        self.provider = provider
    }
}
