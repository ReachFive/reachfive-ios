import Foundation
import AuthenticationServices

public extension ReachFive {

    /// Orchestrates the whole web login: PKCE, authorize URL, web session (via the centralized carrier),
    /// then code exchange. The session is carried by `ReachFive` so that a return via universal link
    /// (received through `application(_:continue:)`) can complete it out-of-band, even for a direct call
    /// to this public API.
    func webviewLogin(_ request: WebviewLoginRequest) async throws -> AuthToken {

        let pkce = Pkce.generate()
        storage.save(key: pkceKey, value: pkce)

        let scope = (request.scope ?? scope)
        let mode = request.webSessionMode
        // `redirect_uri` résolue une fois : celle du mode (lien universel), ou à défaut celle du SdkConfig
        // (custom scheme). Réutilisée à l'identique pour `/authorize`, l'armement hors-bande et l'échange
        // du code (exigence OAuth : les trois doivent coïncider).
        let redirectUri = mode.redirectUri ?? sdkConfig.redirectUri
        let authURL = buildAuthorizeURL(pkce: pkce, state: request.state, nonce: request.nonce, scope: scope, origin: request.origin, provider: request.provider, redirectUri: redirectUri)

        let callbackURL = try await webAuthSession.start(
            url: authURL,
            mode: mode,
            redirectUri: redirectUri,
            presentationContextProvider: request.presentationContextProvider,
            prefersEphemeralWebBrowserSession: request.prefersEphemeralWebBrowserSession)

        let code = try callbackURL.authorizationCode()
        return try await self.authWithCode(code: code, pkce: pkce, redirectUri: redirectUri)
    }
}
