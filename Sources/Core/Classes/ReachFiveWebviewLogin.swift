import Foundation
import AuthenticationServices

public extension ReachFive {

    func webviewLogin(_ request: WebviewLoginRequest) async throws -> AuthToken {

        let pkce = Pkce.generate()
        storage.save(key: pkceKey, value: pkce)

        let scope = (request.scope ?? scope)
        let authURL = buildAuthorizeURL(pkce: pkce, state: request.state, nonce: request.nonce, scope: scope, origin: request.origin, provider: request.provider)

        let callbackURL = try await webAuthSession.start(
            url: authURL,
            presentationContextProvider: request.presentationContextProvider,
            prefersEphemeralWebBrowserSession: request.prefersEphemeralWebBrowserSession)

        let code = try callbackURL.authorizationCode()
        return try await self.authWithCode(code: code, pkce: pkce)
    }
}
