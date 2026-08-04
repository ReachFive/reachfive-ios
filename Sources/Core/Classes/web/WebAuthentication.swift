import AuthenticationServices

/// Carries the web login in progress: starts an `ASWebAuthenticationSession`, waits for its callback, and
/// lets a link received through `application(_:open:)` complete it (``tryComplete(externalCallbackURL:)``).
///
/// **A custom-scheme login arms both channels.** A provider may decide *midway*, sheet already open,
/// whether it finishes inside the sheet or leaves the app for a third-party one — b.connect picks
/// `passive`/`active` only after `/authorize`. The caller therefore cannot pick the channel up front, and
/// does not have to. A universal-link login is the exception: it is built with `callback: .https(...)`, so
/// the sheet itself intercepts the redirection and no out-of-band channel is armed for it.
///
/// **One login at a time, the incumbent keeps its place, and the newcomer is dropped silently.** A
/// `start(...)` called while another login is in progress ends with `.AuthCanceled` — the error every
/// integration already treats as "nothing happened" — and the login already under way is left alone. The
/// caller has nothing to do about it: this is the SDK absorbing a double tap, not a failure to report.
///
/// Refusing rather than replacing is the fix for a concrete bug. Replacing the incumbent means cancelling
/// its sheet and presenting the replacement right behind it; `session.start()` then answers `false` while the
/// outgoing sheet is still animating away, and retrying until it answers `true` only moves the failure —
/// the presentation fails asynchronously in the completion handler with `presentationContextInvalid`, and
/// *both* logins are lost. Measured on an iOS device with two very fast taps on the same web-login button
/// (not reproducible on Mac Catalyst). Refusing the newcomer removes the cancel-then-present sequence
/// altogether, which is the only way found to remove the failure rather than race with it — and on a double
/// tap the first tap is the one the user meant anyway.
///
/// Every other concurrent caller would be programmatic, and there is none: a logout is always a manual
/// action, so it cannot be triggered while a login sheet is on screen. Multi-window setups (iPad,
/// Mac Catalyst) are the one place where two concurrent logins would be legitimate; they are out of scope
/// while a single session is shared by the whole `ReachFive` instance.
///
/// The way out, if a login somehow never resolves: cancel the `Task` that started it. `onCancel` closes the
/// sheet and resumes with `.AuthCanceled`, which frees the slot — a view being torn down does this on its
/// own, and no extra API is needed for it.
///
/// Late or duplicated callbacks are neutralised by ``State``: a resolution has to name the login it belongs
/// to (`Login.id`), and the winning one puts the state back to `idle`, so any later arrival finds nothing to
/// resolve.
///
/// **The out-of-band channel is only armed for a login**: `logout` also goes through `start(...)`, but with
/// `expectsAuthorizationCode: false`. Its callback (`post_logout_redirect_uri`) carries no `code` and is
/// intercepted by the sheet itself, so `expectedCallback` stays `nil`.
///
/// **Accepted imprecision in the matching**: arming `expectedCallback` for *every* web login widens the
/// window in which a passwordless magic link, tapped while a sheet is open, would be consumed by
/// `tryComplete` instead of being routed to `interceptPasswordless` (``ReachFive/interceptUrl(_:)``).
///
/// **Limitation (out-of-band)**: the state of a login in progress only lives in memory. If iOS kills the app
/// during the detour outside it, the callback received on relaunch matches nothing (`tryComplete` returns
/// `false`, the host app routes the link). It is then *accidentally* rescued: `webviewLogin` left its PKCE
/// in the passwordless storage slot, so `interceptPasswordless` completes the login and delivers the token
/// on the `passwordlessCallback` — a web login surfacing on the passwordless channel, which no caller asked
/// for. That accident is the one thing standing between this limitation and a lost `code`, and the real
/// detour can be long, so the window is not negligible. A proper
/// resume after relaunch would mean persisting the login in progress (redirect_uri + PKCE, already in
/// storage) and a channel to deliver the result to the app. Both the accident and the proper fix are out of
/// scope here; see the PKCE storage-slot redesign.
///
/// `@MainActor`: the whole `ASWebAuthenticationSession` domain is already main-thread.
@MainActor
final class WebAuthenticationSession {

    /// Whether a login is in progress, and everything its resolution needs — as **one** value rather than an
    /// agreement to maintain by hand between a session, a continuation, an expected callback and a boolean.
    /// Being `idle` and holding a continuation is not a state that can be written.
    private enum State {
        case idle

        /// `start(...)` was accepted and the slot is taken, but the continuation does not exist yet: it is
        /// only handed to us inside `withCheckedThrowingContinuation`. Nothing else runs on the main actor
        /// between the two, so no resolution can observe this state — it exists so the slot can be claimed
        /// *before* the first suspension point, which is what a double tap needs.
        case claimed(id: Int)

        /// The continuation is installed; this is the only state a resolution can act on.
        case running(Login)
    }

    private struct Login {
        /// Identifies the login; a callback capturing a stale `id` is ignored.
        let id: Int
        let continuation: CheckedContinuation<URL, Error>
        /// The `redirect_uri` expected out-of-band; `nil` for a universal-link login (the sheet intercepts
        /// the redirection itself) → `tryComplete` then matches nothing.
        let expectedCallback: URL?
        /// The presented session, to be closed if a resolution comes from somewhere else. Set back to `nil`
        /// as soon as the session reports its own completion: its sheet is then already on its way out, and
        /// `cancel()`ing it at that point makes UIKit load the view of a deallocating
        /// `SFAuthenticationViewController`.
        var session: ASWebAuthenticationSession?
    }

    /// Whether the slot is taken, for a caller that has side effects to arm *before* presenting and must not
    /// arm them for a call `start(...)` is going to drop (see `webviewLogin` and the shared PKCE slot).
    /// Internal on purpose: an integrator has nothing to check, a dropped call already ends with
    /// `.AuthCanceled`.
    var isLoginInProgress: Bool {
        if case .idle = state { false } else { true }
    }

    private var state = State.idle
    /// Monotonic, never reset: a fresh identity for each accepted login, so the callback of a session
    /// belonging to a previous one can never resolve a newer login.
    private var lastLoginId = 0
    private let baseScheme: String
    /// The `SdkConfig`'s `redirect_uri`, which is the one a custom-scheme login uses.
    private let sdkRedirectUri: URL

    nonisolated init(baseScheme: String, sdkRedirectUri: URL) {
        self.baseScheme = baseScheme
        self.sdkRedirectUri = sdkRedirectUri
    }

    /// Starts a web login and waits for its callback (success, error or cancellation). The
    /// ``WebSessionMode`` describes the shape of the callback (custom scheme or universal link) and drives
    /// how the session is built. For a custom scheme both channels are armed: the sheet intercepts if the
    /// flow never leaves it, and ``tryComplete(externalCallbackURL:)`` resolves if the return comes back
    /// out-of-band — a provider can pick either one midway, sheet already open. If the calling `Task` is
    /// cancelled (view torn down, timeout…), the sheet is closed and the call ends with `.AuthCanceled`.
    ///
    /// - Parameter expectsAuthorizationCode: `false` for a call whose callback carries no `code` (logout):
    ///   the out-of-band channel is then not armed at all.
    /// - Throws: `.AuthCanceled` when a web login is already in progress — the call is dropped and the
    ///   login under way is untouched. Callers do not have to single this case out: it is the same
    ///   "nothing happened" outcome as a user tapping Cancel.
    func start(url: URL,
               mode: WebSessionMode,
               expectsAuthorizationCode: Bool = true,
               presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
               prefersEphemeralWebBrowserSession: Bool = false) async throws -> URL {

        // An already-cancelled Task must not present a sheet (its `onCancel` below would have fired
        // already, to no effect, before the continuation was installed).
        try Task.checkCancellation()

        // One login at a time, and the incumbent keeps its place. Silently: a second call is a double tap,
        // and `.AuthCanceled` is what every integration already ignores.
        guard case .idle = state else {
            Logger.shared.log("A web login is already in progress; this call is dropped. Nothing to handle: the login under way keeps the slot.")
            throw ReachFiveError.AuthCanceled
        }

        // Built before the slot is claimed, so its only failure path — a universal-link callback this OS or
        // this URL cannot support — throws without leaving a slot to release or a continuation to resume.
        let id = lastLoginId + 1
        let prepared = try prepareSession(id: id,
                                         url: url,
                                         mode: mode,
                                         expectsAuthorizationCode: expectsAuthorizationCode,
                                         presentationContextProvider: presentationContextProvider,
                                         prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession)
        lastLoginId = id
        state = .claimed(id: id)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.state = .running(Login(id: id,
                                            continuation: continuation,
                                            expectedCallback: prepared.expectedCallback,
                                            session: prepared.session))

                if !prepared.session.start() {
                    // When start() returns false the completion handler may never be called, so the
                    // continuation is resumed with an error here.
                    self.complete(id: id, .failure(.TechnicalError(reason: "ASWebAuthenticationSession failed to start")))
                }
            }
        } onCancel: {
            // Cancellation can arrive on any thread → hop onto the main actor. No effect if the login is
            // already resolved (`complete`'s guard).
            Task { @MainActor in
                self.complete(id: id, .failure(.AuthCanceled))
            }
        }
    }

    /// Builds the session for `mode` and says which `redirect_uri`, if any, the out-of-band channel should
    /// watch for. Deliberately free of any state mutation: `start(...)` calls it before claiming the slot.
    private func prepareSession(id: Int,
                                url: URL,
                                mode: WebSessionMode,
                                expectsAuthorizationCode: Bool,
                                presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
                                prefersEphemeralWebBrowserSession: Bool)
    throws -> (session: ASWebAuthenticationSession, expectedCallback: URL?) {

        let completionHandler: ASWebAuthenticationSession.CompletionHandler = { [weak self] callbackURL, error in
            // Everything hops to the main thread to avoid races.
            Task { @MainActor in
                self?.handleSessionCompletion(id: id, callbackURL: callbackURL, error: error)
            }
        }

        let session: ASWebAuthenticationSession
        let expectedCallback: URL?
        switch mode.callback {
        case .customScheme:
            // Arm the out-of-band channel: the provider may decide midway to leave for a third-party app,
            // sheet already open, and come back through `application(_:open:)`.
            expectedCallback = expectsAuthorizationCode ? sdkRedirectUri : nil
            session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: baseScheme,
                completionHandler: completionHandler)

        case let .universalLink(callback):
            guard #available(iOS 17.4, *), let host = callback.host else {
                throw ReachFiveError.TechnicalError(reason: "Universal link callback requires iOS 17.4+ and a host: \(callback)")
            }
            // No out-of-band channel to arm: `callback: .https(...)` makes the sheet itself intercept the
            // redirection, and nothing else can deliver that link to us — `application(_:open:)` never
            // sees https URLs.
            expectedCallback = nil
            session = ASWebAuthenticationSession(
                url: url,
                callback: .https(host: host, path: callback.path),
                completionHandler: completionHandler)
        }

        // The window that acts as the session's presentation anchor.
        session.presentationContextProvider = presentationContextProvider
        session.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
        return (session, expectedCallback)
    }

    /// Completes the login in progress if the incoming URL really is our callback, and closes the sheet if it
    /// is still open. Returns `true` only in that case — otherwise `false`, so the host app can route the
    /// link itself.
    func tryComplete(externalCallbackURL url: URL) -> Bool {
        guard case let .running(login) = state,
              let expectedCallback = login.expectedCallback,
              Self.isOurCallback(url, expectedCallback: expectedCallback) else {
            return false
        }
        complete(id: login.id, .success(url))
        return true
    }

    private func handleSessionCompletion(id: Int, callbackURL: URL?, error: Error?) {
        // The session reported, so its sheet is already going away: forget it, so the resolution below does
        // not `cancel()` a session the system is done with (see `Login.session`).
        if case var .running(login) = state, login.id == id {
            login.session = nil
            state = .running(login)
        }

        if let error {
            complete(id: id, .failure(Self.reachFiveError(for: error)))
        } else if let callbackURL {
            complete(id: id, .success(callbackURL))
        } else {
            complete(id: id, .failure(.TechnicalError(reason: "No callback URL")))
        }
    }

    /// The single resolution point: resumes the continuation with `result`, releases the slot, and closes the
    /// sheet if it is still presented (out-of-band resolution, cancellation).
    private func complete(id: Int, _ result: Result<URL, ReachFiveError>) {
        // Ignore a stale callback (it names a login that is no longer the one in place) or a second
        // resolution (the state is back to `idle`).
        guard case let .running(login) = state, login.id == id else { return }
        // Released before the resume so the slot is free for whatever the caller does next.
        state = .idle
        login.continuation.resume(with: result)
        // Only reached when the resolution came from somewhere other than the session itself, which is why
        // this cannot land on a session that has already reported.
        login.session?.cancel()
    }

    /// `true` when the incoming URL designates the same endpoint as the `redirect_uri` we sent
    /// (``matchesEndpoint(of:)``, the matcher shared with ``ReachFive/interceptUrl(_:)``) and carries a
    /// `code` (success) or an `error` parameter (OAuth refusal, e.g. `access_denied` — the login then ends
    /// cleanly with the callback's `ApiError` instead of hanging on the sheet). Comparing the scheme keeps a
    /// login expected on a custom scheme from matching an https URL, and the other way round. Since the
    /// expected path is the one we declare (the redirect_uri), this matching is enough to tell our callback
    /// apart from the app's other links.
    nonisolated static func isOurCallback(_ url: URL, expectedCallback expected: URL) -> Bool {
        url.matchesEndpoint(of: expected)
        && (url.queryValue("code") != nil || url.queryValue("error") != nil)
    }

    /// Maps an `ASWebAuthenticationSession` error onto a `ReachFiveError`.
    ///
    /// `canceledLogin` is not only "the user tapped Cancel": the system also reports it when the app is not
    /// associated with the host of an `.https` callback (measured on iOS and Mac Catalyst — the reason only
    /// appears in `localizedDescription`). It is logged here so a misconfigured Associated Domain does not
    /// vanish into the `.AuthCanceled` every integration ignores.
    nonisolated static func reachFiveError(for error: Error) -> ReachFiveError {
        guard let sessionError = error as? ASWebAuthenticationSessionError else {
            return .TechnicalError(reason: "Unknown Error \(error.localizedDescription)")
        }
        switch sessionError.code {
        case .canceledLogin:
            Logger.shared.log("The web session ended without a callback: \(error.localizedDescription)")
            return .AuthCanceled
        case .presentationContextNotProvided:
            return .TechnicalError(reason: "Presentation context not provided: \(error.localizedDescription)")
        case .presentationContextInvalid:
            return .TechnicalError(reason: "Presentation context invalid: \(error.localizedDescription)")
        @unknown default:
            return .TechnicalError(reason: "Unknown Error \(error.localizedDescription)")
        }
    }
}
