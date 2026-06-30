import Foundation
import AuthenticationServices

public class WebviewLoginRequest {
    public let state: String
    public let nonce: String
    public let scope: [String]?
    public let presentationContextProvider: ASWebAuthenticationPresentationContextProviding
    public let origin: String?
    public let provider: String?
    public let prefersEphemeralWebBrowserSession: Bool
    /// OAuth `redirect_uri` for this login. Must be one of the client's allowed callback URLs, and is
    /// reused identically for the token exchange. Defaults (nil) to `sdkConfig.redirectUri` (the custom
    /// scheme). For a provider whose flow returns via a universal link, set it to that universal link.
    public let redirectUri: String?

    public init(state: String? = nil, nonce: String? = nil, scope: [String]? = nil, presentationContextProvider: ASWebAuthenticationPresentationContextProviding, origin: String? = nil, provider: String? = nil, prefersEphemeralWebBrowserSession: Bool = false, redirectUri: String? = nil) {
        self.state = state ?? "state"
        self.nonce = nonce ?? "nonce"
        self.scope = scope
        self.presentationContextProvider = presentationContextProvider
        self.origin = origin
        self.provider = provider
        self.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
        self.redirectUri = redirectUri
    }
}
