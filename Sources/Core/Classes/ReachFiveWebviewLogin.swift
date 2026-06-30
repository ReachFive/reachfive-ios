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
        // Source de vérité unique : le redirect_uri est résolu et parsé une seule fois ; la chaîne sert
        // pour /authorize et l'échange du code, l'URL parsée pour le callback `.https` in-band et la
        // reconnaissance du callback hors-bande (host/path).
        let redirectUri = request.redirectUri ?? sdkConfig.redirectUri
        let authURL = buildAuthorizeURL(pkce: pkce, state: request.state, nonce: request.nonce, scope: scope, origin: request.origin, provider: request.provider, redirectUri: redirectUri)

        let callbackURL = try await webAuthSessionHolder.run(
            url: authURL,
            expectedCallback: URL(string: redirectUri),
            callbackURLScheme: reachFiveApi.sdkConfig.baseScheme,
            presentationContextProvider: request.presentationContextProvider,
            prefersEphemeralWebBrowserSession: request.prefersEphemeralWebBrowserSession)

        let params = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true)?.queryItems
        guard let params, let code = params.first(where: { $0.name == "code" })?.value else {
            throw ReachFiveError.TechnicalError(reason: "No authorization code", apiError: ApiError(fromQueryParams: params))
        }

        return try await self.authWithCode(code: code, pkce: pkce, redirectUri: redirectUri)
    }
}
