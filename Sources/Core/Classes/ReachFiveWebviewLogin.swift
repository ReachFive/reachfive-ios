import Foundation
import AuthenticationServices

public extension ReachFive {

    /// Orchestrates the whole web login: PKCE, authorize URL, web session (via the centralized carrier),
    /// then code exchange. The session is carried by `ReachFive` so that a callback arriving *outside* the
    /// sheet — through `application(_:open:)`, when a third-party app detour sends the user back via the
    /// default browser — can complete it, even for a direct call to this public API.
    func webviewLogin(_ request: WebviewLoginRequest) async throws -> AuthToken {

        // Dropped here rather than by `webAuthSession.start(...)`, because the PKCE write below has to happen
        // before the sheet opens and lands in a slot shared by every authorize-style flow (see the FIXME): a
        // call that is going to be dropped must not leave its PKCE where the login under way expects its own.
        // Measured on a device: the first web login waits on iOS launching its browser process, and an
        // impatient user taps a couple of dozen more times meanwhile — that many overwrites otherwise.
        // Not airtight: reading the session suspends, so two calls in the same turn both get past this and
        // are only told apart by `start(...)`.
        guard !(await webAuthSession.isLoginInProgress) else {
            Logger.shared.log("A web login is already in progress; this call is dropped before arming anything.")
            throw ReachFiveError.AuthCanceled
        }

        let pkce = Pkce.generate()
        // FIXME: this write lands in the *passwordless* PKCE slot, shared by every authorize-style flow, which
        // makes three behaviours possible:
        //   - intentional: a magic link tapped after the hosted login page switched to passwordless is
        //     completed by `interceptPasswordless` using this PKCE;
        //   - not intentional: the `code` gets rescued on a channel no caller asked for. The active b.connect
        //     detour finishes on its own whatever we do to the sheet — the bank app, then the default browser,
        //     carry the rest of the chain and deliver the callback to `application(_:open:)` regardless. If
        //     the slot is empty by then (the login cancelled locally at any point of the detour, or the app
        //     killed and relaunched by the link itself), `tryComplete` matches nothing and `routeUrl` hands our
        //     own callback to `interceptPasswordless`, which delivers this web login's token on the
        //     `passwordlessCallback`;
        //   - not intentional: starting a web login while a passwordless is pending overwrites its PKCE, so
        //     its magic link then fails.
        // The guard above keeps a dropped call from adding a fourth. The fix is a slot per flow instead of one
        // shared key, which would also let the login in progress be persisted and resumed after an app kill:
        // see the storage-slot redesign.
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
