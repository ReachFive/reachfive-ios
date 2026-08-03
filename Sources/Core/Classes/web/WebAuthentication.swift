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
/// **One login at a time.** On iPhone, the modal sheet of an `ASWebAuthenticationSession` puts a second
/// `start(...)` out of reach of user interaction: while it is presented nothing else can be triggered, and
/// it only goes away through a resolution (callback, Cancel) that resumes the continuation. What remains is
/// **programmatic** calls (a logout/login driven by app logic without interaction, a double invocation),
/// multi-window setups (iPad/macCatalyst), and a completion handler the system would never call back. In
/// all of those the last caller wins: the previous login is resumed with `.AuthCanceled` and its sheet is
/// closed, so no continuation ever freezes.
///
/// Late or duplicated callbacks are neutralised two ways: a **per-attempt token** (`attempt`), so the
/// callback of a stale `ASWebAuthenticationSession` can never resume a newer login's continuation, and
/// setting `continuation` back to `nil` in `complete(_:)`, so the winning resolution (in the sheet,
/// out-of-band, or a cancellation) resumes the continuation exactly once.
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
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    /// The `redirect_uri` expected for this attempt; `nil` outside a login, or for a universal-link login
    /// (which has no out-of-band channel) → `tryComplete` then matches nothing.
    private var expectedCallback: URL?
    /// Identifies the attempt in progress; a callback capturing a stale `attempt` is ignored.
    private var attempt = 0
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
    func start(url: URL,
               mode: WebSessionMode,
               expectsAuthorizationCode: Bool = true,
               presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
               prefersEphemeralWebBrowserSession: Bool = false) async throws -> URL {

        // An already-cancelled Task must not present a sheet (its `onCancel` below would have fired
        // already, to no effect, before the continuation was installed).
        try Task.checkCancellation()

        // Last caller wins: resume any login still pending with `.AuthCanceled` and close its sheet, so a
        // continuation is never left frozen without a resolution.
        complete(attempt: attempt, .failure(.AuthCanceled))
        attempt += 1
        let attempt = attempt

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation

                let completionHandler: ASWebAuthenticationSession.CompletionHandler = { [weak self] callbackURL, error in
                    // Everything hops to the main thread to avoid races.
                    Task { @MainActor in
                        self?.handleSessionCompletion(attempt: attempt, callbackURL: callbackURL, error: error)
                    }
                }

                // A factory, not a session: a session the system refused to present is not documented as
                // replayable, so a fresh one is built for each presentation attempt (see `present`).
                let makeSession: () -> ASWebAuthenticationSession
                switch mode.callback {
                case .customScheme:
                    // Arm the out-of-band channel: the provider may decide midway to leave for a
                    // third-party app, sheet already open, and come back through `application(_:open:)`.
                    self.expectedCallback = expectsAuthorizationCode ? sdkRedirectUri : nil
                    makeSession = {
                        ASWebAuthenticationSession(
                            url: url,
                            callbackURLScheme: self.baseScheme,
                            completionHandler: completionHandler)
                    }

                case let .universalLink(callback):
                    guard #available(iOS 17.4, *), let host = callback.host else {
                        self.complete(attempt: attempt, .failure(.TechnicalError(reason: "Universal link callback requires iOS 17.4+ and a host: \(callback)")))
                        return
                    }
                    // No out-of-band channel to arm: `callback: .https(...)` makes the sheet itself
                    // intercept the redirection, and nothing else can deliver that link to us —
                    // `application(_:open:)` never sees https URLs.
                    self.expectedCallback = nil
                    makeSession = {
                        ASWebAuthenticationSession(
                            url: url,
                            callback: .https(host: host, path: callback.path),
                            completionHandler: completionHandler)
                    }
                }

                self.present(attempt: attempt,
                             remainingAttempts: Self.presentationAttempts,
                             makeSession: makeSession,
                             presentationContextProvider: presentationContextProvider,
                             prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession)
            }
        } onCancel: {
            // Cancellation can arrive on any thread → hop onto the main actor. No effect if the attempt is
            // already resolved or was replaced by a newer login (`complete`'s guards).
            Task { @MainActor in
                self.complete(attempt: attempt, .failure(.AuthCanceled))
            }
        }
    }

    /// Completes the login in progress if the incoming URL really is our callback, and closes the sheet if it
    /// is still open. Returns `true` only in that case — otherwise `false`, so the host app can route the
    /// link itself.
    func tryComplete(externalCallbackURL url: URL) -> Bool {
        guard let expectedCallback,
              Self.isOurCallback(url, expectedCallback: expectedCallback) else {
            return false
        }
        complete(attempt: attempt, .success(url))
        return true
    }

    /// Presents the sheet, retrying while the system refuses to present it.
    ///
    /// When `start(...)` has just replaced a login, the previous sheet is still being dismissed — an
    /// asynchronous, animated dismissal — and `session.start()` answers `false`. That is the only reliable
    /// "not ready yet" signal, so we wait and try again instead of betting on an animation duration. The
    /// outgoing sheet's completion handler is not a safer barrier: it marks the end of the *session*, not
    /// the end of the dismissal animation.
    ///
    /// How to reproduce the case: two very fast taps on the same web-login button (on an iOS device; not
    /// reproducible on Mac Catalyst).
    private func present(attempt: Int,
                         remainingAttempts: Int,
                         makeSession: @escaping () -> ASWebAuthenticationSession,
                         presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
                         prefersEphemeralWebBrowserSession: Bool) {
        let session = makeSession()
        // The window that acts as the session's presentation anchor.
        session.presentationContextProvider = presentationContextProvider
        session.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
        self.session = session

        if session.start() {
            return
        }

        guard remainingAttempts > 1 else {
            // When start() returns false the completion handler may never be called, so the continuation is
            // resumed with an error here.
            complete(attempt: attempt, .failure(.TechnicalError(reason: "ASWebAuthenticationSession failed to start")))
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.presentationRetryDelay)
            // No effect if the attempt has been resolved or replaced in the meantime.
            guard attempt == self.attempt, self.continuation != nil else { return }
            self.present(attempt: attempt,
                         remainingAttempts: remainingAttempts - 1,
                         makeSession: makeSession,
                         presentationContextProvider: presentationContextProvider,
                         prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession)
        }
    }

    /// Presentation attempts, and the delay between two: enough to cover the dismissal of a sheet we just
    /// cancelled, without ever looping for long when the refusal has another cause.
    private static let presentationAttempts = 4
    private static let presentationRetryDelay: UInt64 = 150_000_000

    private func handleSessionCompletion(attempt: Int, callbackURL: URL?, error: Error?) {
        if let error {
            complete(attempt: attempt, .failure(Self.reachFiveError(for: error)))
        } else if let callbackURL {
            complete(attempt: attempt, .success(callbackURL))
        } else {
            complete(attempt: attempt, .failure(.TechnicalError(reason: "No callback URL")))
        }
    }

    /// The single resolution point: resumes the continuation with `result`, clears the state, and closes the
    /// sheet if it is still presented (out-of-band resolution, cancellation, replacement).
    private func complete(attempt: Int, _ result: Result<URL, ReachFiveError>) {
        // Ignore a stale callback (a newer login came in) or a second resolution (`continuation` already nil).
        guard attempt == self.attempt, let continuation else { return }
        // Capture the session before nil-ing it, to close its sheet after the resume. The late cancellation
        // callback that results is ignored (`continuation` is nil by then); on a session that is already
        // finished or was never presented, `cancel()` does nothing.
        let openSession = session
        self.continuation = nil
        self.session = nil
        self.expectedCallback = nil
        continuation.resume(with: result)
        openSession?.cancel()
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
    nonisolated static func reachFiveError(for error: Error) -> ReachFiveError {
        guard let sessionError = error as? ASWebAuthenticationSessionError else {
            return .TechnicalError(reason: "Unknown Error \(error.localizedDescription)")
        }
        switch sessionError.code {
        case .canceledLogin:
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
