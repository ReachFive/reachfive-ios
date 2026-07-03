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
    /// Le `redirect_uri` de ce login et son canal de retour. Le `redirect_uri` résolu doit faire partie
    /// des callback URLs autorisées du client, et est réutilisé à l'identique pour l'échange du code.
    /// Défaut : ``WebSessionMode/sdkScheme``.
    public let webSessionMode: WebSessionMode

    public init(
        state: String? = nil,
        nonce: String? = nil,
        scope: [String]? = nil,
        presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
        origin: String? = nil,
        provider: String? = nil,
        prefersEphemeralWebBrowserSession: Bool = false,
        webSessionMode: WebSessionMode = .sdkScheme
    ) {
        self.state = state ?? "state"
        self.nonce = nonce ?? "nonce"
        self.scope = scope
        self.presentationContextProvider = presentationContextProvider
        self.origin = origin
        self.provider = provider
        self.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
        self.webSessionMode = webSessionMode
    }
}
