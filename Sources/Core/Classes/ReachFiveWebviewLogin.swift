import Foundation
import AuthenticationServices

public extension ReachFive {

    /// Orchestrates the whole web login: PKCE, authorize URL, web session (via the centralized carrier),
    /// then code exchange. The session is carried by `ReachFive` so that a callback arriving *outside* the
    /// sheet — through `application(_:open:)`, when a third-party app detour sends the user back via the
    /// default browser — can complete it, even for a direct call to this public API.
    func webviewLogin(_ request: WebviewLoginRequest) async throws -> AuthToken {

        let pkce = Pkce.generate()
        // FIXME: this write lands in the *passwordless* PKCE slot, shared by every authorize-style flow.
        // Two behaviours follows:
        //   - a magic link tapped after the hosted login page switched to passwordless is completed by
        //     `interceptPasswordless` using this PKCE;
        //   - if iOS kills the app mid-detour, the callback received on relaunch is likewise completed by
        //     `interceptPasswordless`, delivering this web login's token on the `passwordlessCallback`.
        // The first is intentional, but the second is not.
        // And it seems that starting a web login while a passwordless is pending overwrites the PKCE, so its magic link then fails.
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
