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
        let mode = request.webSessionMode
        let authURL = buildAuthorizeURL(pkce: pkce, state: request.state, nonce: request.nonce, scope: scope, origin: request.origin, provider: request.provider, redirectUri: mode.redirectUri)

        let callbackURL = try await webAuthSession.start(
            url: authURL,
            mode: mode,
            presentationContextProvider: request.presentationContextProvider,
            prefersEphemeralWebBrowserSession: request.prefersEphemeralWebBrowserSession)

        let code = try callbackURL.authorizationCode()
        return try await self.authWithCode(code: code, pkce: pkce, redirectUri: mode.redirectUri)
    }
}
