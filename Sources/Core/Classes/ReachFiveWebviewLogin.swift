import Foundation
import AuthenticationServices

public extension ReachFive {

    /// Orchestrates the whole web login: PKCE, authorize URL, web session (via the centralized carrier),
    /// then code exchange. The session is carried by `ReachFive` so that a callback arriving *outside* the
    /// sheet — through `application(_:open:)`, when a third-party app detour sends the user back via the
    /// default browser — can complete it, even for a direct call to this public API.
    func webviewLogin(_ request: WebviewLoginRequest) async throws -> AuthToken {

        // Asked here and not only inside `webAuthSession.start(...)`, because the PKCE write below has to
        // happen before the sheet opens and lands in a slot shared by every authorize-style flow: a call that
        // is going to be dropped must not leave its PKCE where the login already under way expects its own.
        // Measured on a device: the first web login of a session waits on iOS launching its browser process,
        // and an impatient user taps a couple of dozen more times before the sheet appears — that many
        // overwrites, one per dropped call.
        //
        // Not airtight: reading the session suspends, so two calls in the same turn can still both get past
        // this and only be told apart by `start(...)`. Closing that window means arming the storage in the
        // same main-actor turn as the slot, which the shared slot makes pointless — see the FIXME below.
        guard !(await webAuthSession.isLoginInProgress) else {
            Logger.shared.log("A web login is already in progress; this call is dropped before arming anything.")
            throw ReachFiveError.AuthCanceled
        }

        let pkce = Pkce.generate()
        // FIXME: this write lands in the *passwordless* PKCE slot, shared by every authorize-style flow.
        // Two behaviours follows:
        //   - a magic link tapped after the hosted login page switched to passwordless is completed by
        //     `interceptPasswordless` using this PKCE;
        //   - if iOS kills the app mid-detour, the callback received on relaunch is likewise completed by
        //     `interceptPasswordless`, delivering this web login's token on the `passwordlessCallback`.
        // The first is intentional, but the second is not.
        // And it seems that starting a web login while a passwordless is pending overwrites the PKCE, so its magic link then fails.
        // Same cause, one more consequence: this write happens *before* `webAuthSession.start(...)` can drop
        // the call, because the PKCE has to be in storage while the sheet is open. On a double tap the
        // dropped call therefore leaves its own PKCE behind, and the login that survives no longer matches
        // what the slot holds — so both rescues above would fail for it. Fixing the ordering needs a slot
        // per login rather than one shared key, i.e. the storage-slot redesign.
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
