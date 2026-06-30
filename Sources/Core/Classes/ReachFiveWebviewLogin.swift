import Foundation
import AuthenticationServices

public extension ReachFive {

    /// Orchestre tout le login web : PKCE, URL d'autorize, session web (via le `WebAuthSessionStore`
    /// centralisé), puis échange du code. Le `state` sert de clé de corrélation pour reconnaître/router
    /// le callback, ce qui permet la complétion hors-bande (universal link reçu via
    /// `application(_:continue:)`) même pour un appel direct de cette API publique.
    func webviewLogin(_ request: WebviewLoginRequest) async throws -> AuthToken {

        let pkce = Pkce.generate()
        storage.save(key: pkceKey, value: pkce)

        let scope = (request.scope ?? scope)
        // Source de vérité unique : le redirect_uri est résolu et parsé une seule fois ; la chaîne sert
        // pour /authorize et l'échange du code, l'URL parsée pour le callback `.https` in-band (host/path).
        let redirectUri = request.redirectUri ?? sdkConfig.redirectUri
        let authURL = buildAuthorizeURL(pkce: pkce, state: request.state, nonce: request.nonce, scope: scope, origin: request.origin, provider: request.provider, redirectUri: redirectUri)

        let routing = WebAuthRouting(state: request.state, expectedCallback: URL(string: redirectUri))

        let callbackURL = try await webAuthSessionStore.run(
            routing: routing,
            url: authURL,
            callbackURLScheme: reachFiveApi.sdkConfig.baseScheme,
            presentationContextProvider: request.presentationContextProvider,
            prefersEphemeralWebBrowserSession: request.prefersEphemeralWebBrowserSession)

        // Cohérence du routage : le `state` renvoyé doit correspondre à celui émis (la CSRF, elle, est
        // couverte par PKCE).
        if let returnedState = callbackURL.queryValue("state"), returnedState != request.state {
            throw ReachFiveError.TechnicalError(reason: "Invalid state")
        }

        let params = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true)?.queryItems
        guard let params, let code = params.first(where: { $0.name == "code" })?.value else {
            throw ReachFiveError.TechnicalError(reason: "No authorization code", apiError: ApiError(fromQueryParams: params))
        }

        return try await self.authWithCode(code: code, pkce: pkce, redirectUri: redirectUri)
    }
}
