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
    /// The `redirect_uri` of this login and its return channel. The resolved `redirect_uri` must be one
    /// of the client's authorized callback URLs, and is reused identically for the code exchange.
    /// Default: ``WebSessionMode/sdkScheme``.
    public let webSessionMode: WebSessionMode
    /// Key/value pairs propagated in the **fragment** of the `/oauth/authorize` URL (`#key=value&key2=value2`).
    /// Intended for the token-orchestration flow: `/oauth/authorize` 302-redirects to the client's Login URL,
    /// and a fragment (unlike a query param) survives that redirect — the browser re-applies it onto the
    /// redirect target. The Login URL can then read it via `window.location.hash` to customize the page per
    /// calling channel (logo/colors). Ignored when the client has no token orchestration configured.
    public let loginUrlFragment: [String: String]?

    public init(
        state: String? = nil,
        nonce: String? = nil,
        scope: [String]? = nil,
        presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
        origin: String? = nil,
        provider: String? = nil,
        prefersEphemeralWebBrowserSession: Bool = false,
        webSessionMode: WebSessionMode = .sdkScheme,
        loginUrlFragment: [String: String]? = nil
    ) {
        self.state = state ?? "state"
        self.nonce = nonce ?? "nonce"
        self.scope = scope
        self.presentationContextProvider = presentationContextProvider
        self.origin = origin
        self.provider = provider
        self.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
        self.webSessionMode = webSessionMode
        self.loginUrlFragment = loginUrlFragment
    }
}
