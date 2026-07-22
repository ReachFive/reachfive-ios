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
        let authURL = buildAuthorizeURL(pkce: pkce, state: request.state, nonce: request.nonce, scope: scope, origin: request.origin, provider: request.provider, redirectUri: mode.redirectUri, loginUrlFragment: request.loginUrlFragment)

        let callbackURL = try await webAuthSession.start(
            url: authURL,
            mode: mode,
            presentationContextProvider: request.presentationContextProvider,
            prefersEphemeralWebBrowserSession: request.prefersEphemeralWebBrowserSession)

        let code = try callbackURL.authorizationCode()
        return try await self.authWithCode(code: code, pkce: pkce, redirectUri: mode.redirectUri)
    }
}
