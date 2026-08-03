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
/// **One login at a time, and the incumbent keeps its place.** A `start(...)` called while another login is
/// in progress fails immediately with a `.TechnicalError`; the login already under way is left alone.
///
/// This is not a taste for strictness, it is the fix for a concrete bug. Replacing the incumbent means
/// cancelling its sheet and presenting the replacement right behind it, and iOS then loads the view of the
/// outgoing `SFAuthenticationViewController` while it is deallocating. `session.start()` still answers
/// `true`, so there is nothing to retry on; the failure lands asynchronously in the completion handler as
/// `presentationContextInvalid`, and *both* logins are lost. Reproduced with two very fast taps on the same
/// web-login button (iOS device; not reproducible on Mac Catalyst). Refusing the newcomer removes the
/// cancel-then-present sequence altogether, which is the only way found to remove the failure rather than
/// race with it — and on a double tap the first tap is the one the user meant anyway.
///
/// The way out, if a login somehow never resolves (a completion handler the system never calls back): cancel
/// the `Task` that started it. `onCancel` closes the sheet and resumes with `.AuthCanceled`, which frees the
/// slot. A view being torn down does this on its own.
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
    /// A login is in progress. Invariant, outside the continuation closure: `loginInProgress` is true exactly
    /// when `continuation` is non-nil — both are set by `start(...)` and both cleared by `complete(_:)`, the
    /// single resolution point.
    ///
    /// It is not, however, redundant with `continuation != nil`, and it is not the old `hasResumed` either
    /// (which was local to one call and guarded exactly-once resumption of a single continuation). What it
    /// buys is that `start(...)` can refuse a second login **before** its first suspension point, and
    /// therefore before `attempt += 1`:
    /// - `continuation` and `session` are only assigned inside the continuation closure, past an `await`, so
    ///   guarding on either would let two calls made in quick succession both through — which is exactly
    ///   what a double tap on a login button produces;
    /// - and bumping `attempt` before refusing would invalidate the token of the login *already in place*:
    ///   its completion handler captured the old value, `complete(attempt:)` would no-op, and its
    ///   continuation would freeze — the very failure the token exists to prevent.
    private var loginInProgress = false
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

        // One login at a time, and the incumbent keeps its place.
        guard !loginInProgress else {
            print("🔍 [WebAuth] start REFUSED — slot still held by attempt \(self.attempt) (continuation=\(continuation != nil), session=\(session != nil))") // TEMP DEBUG
            throw ReachFiveError.TechnicalError(reason: "A web login is already in progress. Wait for it to finish, or cancel the Task that started it.")
        }
        loginInProgress = true
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

                let session: ASWebAuthenticationSession
                switch mode.callback {
                case .customScheme:
                    // Arm the out-of-band channel: the provider may decide midway to leave for a
                    // third-party app, sheet already open, and come back through `application(_:open:)`.
                    self.expectedCallback = expectsAuthorizationCode ? sdkRedirectUri : nil
                    session = ASWebAuthenticationSession(
                        url: url,
                        callbackURLScheme: self.baseScheme,
                        completionHandler: completionHandler)

                case let .universalLink(callback):
                    guard #available(iOS 17.4, *), let host = callback.host else {
                        self.complete(attempt: attempt, .failure(.TechnicalError(reason: "Universal link callback requires iOS 17.4+ and a host: \(callback)")))
                        return
                    }
                    // No out-of-band channel to arm: `callback: .https(...)` makes the sheet itself
                    // intercept the redirection, and nothing else can deliver that link to us —
                    // `application(_:open:)` never sees https URLs.
                    self.expectedCallback = nil
                    session = ASWebAuthenticationSession(
                        url: url,
                        callback: .https(host: host, path: callback.path),
                        completionHandler: completionHandler)
                }

                // The window that acts as the session's presentation anchor.
                session.presentationContextProvider = presentationContextProvider
                session.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
                self.session = session

                let started = session.start() // TEMP DEBUG: hoisted out of the `if` to log the value
                print("🔍 [WebAuth] start() attempt=\(attempt) mode=\(mode.callback) → \(started)") // TEMP DEBUG
                if !started {
                    // When start() returns false the completion handler may never be called, so the
                    // continuation is resumed with an error here.
                    self.complete(attempt: attempt, .failure(.TechnicalError(reason: "ASWebAuthenticationSession failed to start")))
                }
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

    private func handleSessionCompletion(attempt: Int, callbackURL: URL?, error: Error?) {
        // TEMP DEBUG — the system called us back. Absence of this line means the completion handler never fired.
        let ns = error as NSError?
        let asCode = (error as? ASWebAuthenticationSessionError).map { "\($0.code) (\($0.code.rawValue))" } ?? "not an ASWebAuthenticationSessionError"
        print("""
              🔍 [WebAuth] handleSessionCompletion attempt=\(attempt) current=\(self.attempt) \
              loginInProgress=\(loginInProgress) continuation=\(continuation != nil)
                 callbackURL=\(callbackURL?.absoluteString ?? "nil")
                 error=\(ns.map { "\($0.domain) code=\($0.code) — \($0.localizedDescription)" } ?? "nil")
                 asWebAuthError=\(asCode)
              """)

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
        // TEMP DEBUG — did this resolution reach the continuation, or was it dropped (slot stays held)?
        print("🔍 [WebAuth] complete attempt=\(attempt) current=\(self.attempt) continuation=\(continuation != nil) → \(attempt == self.attempt && continuation != nil ? "RESOLVES" : "DROPPED") result=\(result)")

        // Ignore a stale callback (a newer login came in) or a second resolution (`continuation` already nil).
        guard attempt == self.attempt, let continuation else { return }
        // Capture the session before nil-ing it, to close its sheet after the resume. The late cancellation
        // callback that results is ignored (`continuation` is nil by then); on a session that is already
        // finished or was never presented, `cancel()` does nothing.
        let openSession = session
        self.continuation = nil
        self.session = nil
        self.expectedCallback = nil
        self.loginInProgress = false
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
