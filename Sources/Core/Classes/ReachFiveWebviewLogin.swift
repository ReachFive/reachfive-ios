import Foundation
import AuthenticationServices

public extension ReachFive {

    /// Orchestre tout le login web : PKCE, URL d'autorize, session web (via le porteur centralisé),
    /// puis échange du code. La session est portée par `ReachFive` pour qu'un retour par universal link
    /// (reçu via `application(_:continue:)`) puisse la compléter hors-bande, même pour un appel direct
    /// de cette API publique.
    func webviewLogin(_ request: WebviewLoginRequest) async throws -> AuthToken {

        let pkce = Pkce.generate()
        storage.save(key: pkceKey, value: pkce)

        let scope = (request.scope ?? scope)
        // Le callback de la requête donne à la fois le redirect_uri (chaîne, pour /authorize et l'échange
        // du code) et le mode de session (comment la session se termine / par quel canal on reçoit le
        // callback). Un universal link non parsable désactiverait silencieusement la complétion → on
        // échoue tôt avec une erreur claire.
        let redirectUri: String
        let mode: WebSessionMode
        switch request.callback {
        case .sdkScheme:
            redirectUri = sdkConfig.redirectUri
            mode = .inSheet(.scheme(sdkConfig.baseScheme))
        case .universalLinkInSheet(let link):
            guard let url = URL(string: link) else {
                throw ReachFiveError.TechnicalError(reason: "Invalid redirect_uri: \(link)")
            }
            redirectUri = link
            mode = .inSheet(.universalLink(url))
        case .externalApp(let link):
            guard let url = URL(string: link) else {
                throw ReachFiveError.TechnicalError(reason: "Invalid redirect_uri: \(link)")
            }
            redirectUri = link
            mode = .externalApp(url)
        }
        let authURL = buildAuthorizeURL(pkce: pkce, state: request.state, nonce: request.nonce, scope: scope, origin: request.origin, provider: request.provider, redirectUri: redirectUri)

        let callbackURL = try await webAuthSession.start(
            url: authURL,
            mode: mode,
            presentationContextProvider: request.presentationContextProvider,
            prefersEphemeralWebBrowserSession: request.prefersEphemeralWebBrowserSession)

        guard let code = callbackURL.queryValue("code") else {
            let params = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true)?.queryItems
            throw ReachFiveError.TechnicalError(reason: "No authorization code", apiError: ApiError(fromQueryParams: params))
        }

        return try await self.authWithCode(code: code, pkce: pkce, redirectUri: redirectUri)
    }
}
