import Foundation
import AuthenticationServices

/// Décrit le `redirect_uri` OAuth d'un login web ET comment la session web se termine — l'intention
/// du flow, que l'URL seule ne suffit pas à déduire (deux universal links `https` peuvent viser deux
/// canaux de retour différents). Le SDK en dérive le `redirect_uri` (chaîne, pour `/authorize` et
/// l'échange du code) et le mode de session interne.
public enum WebviewCallback {
    /// Défaut : le scheme custom du SDK (`sdkConfig.redirectUri`, ex. `reachfive-<clientId>://callback`),
    /// intercepté directement dans la session web.
    case sdkScheme
    /// Universal link intercepté DANS la feuille : tout le flow se termine dans la session web.
    /// iOS 17.4+ uniquement ; requiert l'Associated Domain `webcredentials:<host>`.
    case universalLinkInSheet(String)
    /// Universal link renvoyé HORS-BANDE par une app externe (ex. B.connect) : la session web est
    /// rouverte via `application(_:continue:)` puis annulée. Requiert l'Associated Domain `applinks:<host>`.
    case externalApp(String)
}

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
    /// Défaut : ``WebviewCallback/sdkScheme``.
    public let callback: WebviewCallback

    public init(state: String? = nil, nonce: String? = nil, scope: [String]? = nil, presentationContextProvider: ASWebAuthenticationPresentationContextProviding, origin: String? = nil, provider: String? = nil, prefersEphemeralWebBrowserSession: Bool = false, callback: WebviewCallback = .sdkScheme) {
        self.state = state ?? "state"
        self.nonce = nonce ?? "nonce"
        self.scope = scope
        self.presentationContextProvider = presentationContextProvider
        self.origin = origin
        self.provider = provider
        self.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
        self.callback = callback
    }
}
