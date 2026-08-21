import AuthenticationServices

/// Carries the web login in progress: starts an `ASWebAuthenticationSession`, waits for its callback, and either complete it locally,
/// or lets a link received through `application(_:open:)` complete it (``tryComplete(externalCallbackURL:)``).
///
/// **A custom-scheme login prepares both channels**, because a provider may decide *midway*, sheet already open,
/// whether it finishes inside the sheet or leaves for a third-party app. Two calls leave the
/// out-of-band channel inactive: a universal-link login, whose `callback: .https(...)` makes the sheet
/// intercept the redirection itself, and `logout`, whose callback carries no `code`
/// (`expectsAuthorizationCode: false`).
///
/// **One login at a time, and the newcomer is dropped silently** with `.AuthCanceled`, leaving the login under way untouched.
/// Nothing is expected of the caller: this is the SDK absorbing a double tap, not a failure to report.
///
/// Refusing rather than replacing is a measured choice. Replacing means cancelling the incumbent's sheet and
/// presenting the newcomer behind it; `session.start()` then answers `false` while the outgoing sheet
/// animates away, and retrying until it answers `true` only moves the failure — the presentation then fails
/// asynchronously with `presentationContextInvalid`, and *both* logins are lost. Reproduced on an iOS device
/// with two fast taps on the same button (never on Mac Catalyst). Refusing removes the cancel-then-present
/// sequence entirely, and on a double tap the first tap is the one the user meant. No legitimate caller wants
/// the other behaviour: a logout is always a manual action, so it cannot start while a login sheet is on
/// screen. Multi-window (iPad, Mac Catalyst) is the one place two concurrent logins would make sense, and is
/// out of scope while one session is shared by the whole `ReachFive` instance.
///
/// The way out if a login never resolves: cancel the `Task` that started it — `onCancel` closes the sheet and
/// frees the slot, which a view being torn down does on its own.
///
/// **Two accepted imprecisions**, both rooted in the shared PKCE slot and described by the FIXME in ``ReachFive/webviewLogin(_:)``
///
/// `@MainActor`: the whole `ASWebAuthenticationSession` domain is already main-thread.
@MainActor
final class WebAuthenticationSession {
    /// Whether a login is in progress, and everything its resolution needs between a session, a continuation, an expected callback and a boolean.
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
        /// The presented session, to close its sheet when the resolution comes from somewhere else
        /// (out-of-band, or the calling `Task` cancelled). Set back to `nil` as soon as the session reports
        /// its own completion: the system is then done with it and there is no sheet left to close.
        var session: ASWebAuthenticationSession?
    }

    /// Whether the slot is taken: a caller must not apply side effects *before* calling a `start(...)` that would  be knwon to be refused (see ``ReachFive/webviewLogin(_:)``).
    /// Internal onpurpose: an integrator has nothing to check, a dropped call already ends with `.AuthCanceled`.
    var isLoginInProgress: Bool {
        if case .idle = state {
            false
        } else {
            true
        }
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
    /// ``WebSessionMode`` drives how the session is built and which channels are prepared, as described above.
    /// If the calling `Task` is cancelled (view torn down, timeout…), the sheet is closed and the call ends
    /// with `.AuthCanceled`.
    ///
    /// - Parameter expectsAuthorizationCode: `false` for a call whose callback carries no `code` (logout):
    ///   the out-of-band channel is then not prepared at all.
    /// - Throws: `.AuthCanceled` when a web login is already in progress — the call is dropped, the login
    ///   under way is untouched, and the caller has nothing to single out — or when the calling `Task` was
    ///   already cancelled, in which case nothing is presented at all.
    func start(
        url: URL,
        mode: WebSessionMode,
        expectsAuthorizationCode: Bool = true,
        presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
        prefersEphemeralWebBrowserSession: Bool = false
    ) async throws -> URL {
        // An already-cancelled Task must not present a sheet (its `onCancel` below would already have run,
        // to no effect, before the continuation was installed).
        guard !Task.isCancelled else { throw ReachFiveError.AuthCanceled }

        // One login at a time, and the incumbent keeps its place.
        guard case .idle = state else {
            Logger.shared.log("A web login is already in progress; this call is dropped, the login under way continues.")
            throw ReachFiveError.AuthCanceled
        }

        // Built before the slot is claimed, so its only failure path — a universal-link callback this OS or
        // this URL cannot support — throws without leaving a slot to release or a continuation to resume.
        let id = lastLoginId + 1
        let prepared = try prepareSession(
            id: id,
            url: url,
            mode: mode,
            expectsAuthorizationCode: expectsAuthorizationCode,
            presentationContextProvider: presentationContextProvider,
            prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession
        )
        lastLoginId = id
        state = .claimed(id: id)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.state = .running(Login(
                    id: id,
                    continuation: continuation,
                    expectedCallback: prepared.expectedCallback,
                    session: prepared.session
                ))

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
    private func prepareSession(
        id: Int,
        url: URL,
        mode: WebSessionMode,
        expectsAuthorizationCode: Bool,
        presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
        prefersEphemeralWebBrowserSession: Bool
    )
        throws -> (session: ASWebAuthenticationSession, expectedCallback: URL?)
    {
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
            // Prepare the out-of-band channel: the provider may decide midway to leave for a third-party app,
            // sheet already open, and come back through `application(_:open:)`.
            expectedCallback = expectsAuthorizationCode ? sdkRedirectUri : nil
            session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: baseScheme,
                completionHandler: completionHandler
            )

        case let .universalLink(callback):
            guard #available(iOS 17.4, *), let host = callback.host else {
                throw ReachFiveError.TechnicalError(reason: "Universal link callback requires iOS 17.4+ and a host: \(callback)")
            }
            // No out-of-band channel to prepare: `callback: .https(...)` makes the sheet itself intercept the
            // redirection, and nothing else can deliver that link to us — `application(_:open:)` never
            // sees https URLs.
            expectedCallback = nil
            session = ASWebAuthenticationSession(
                url: url,
                callback: .https(host: host, path: callback.path),
                completionHandler: completionHandler
            )
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
              Self.isOurCallback(url, expectedCallback: expectedCallback) else
        {
            return false
        }
        complete(id: login.id, .success(url))
        return true
    }

    private func handleSessionCompletion(id: Int, callbackURL: URL?, error: Error?) {
        // A session that is no longer the one in place reports late — typically the `canceledLogin` our own
        // `cancel()` draws after an out-of-band resolution. Nothing to resolve, and nothing worth logging.
        guard case var .running(login) = state, login.id == id else { return }

        // The session reported, so its sheet is already going away: forget it, so the resolution below does
        // not `cancel()` a session the system is done with (see `Login.session`).
        login.session = nil
        state = .running(login)

        if let error {
            // Logged because `.canceledLogin` covers more than the user tapping Cancel: the system also
            // reports it when the app is not associated with the host of an `.https` callback, and the
            // reason only shows up in `localizedDescription`. Only reached for an error this call is about
            // to deliver, so it never runs for a sheet we closed ourselves.
            Logger.shared.log("The web session ended without a callback: \(error.localizedDescription)")
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
        // this cannot land on a session that has already reported. Unrelated to the "Attempting to load the
        // view … while it is deallocating (SFAuthenticationViewController)" iOS logs when tearing a cancelled
        // sheet down: that one shows up on a plain user cancel too, with no `cancel()` of ours involved.
        login.session?.cancel()
    }

    /// `true` when the incoming URL designates the same endpoint as the `redirect_uri` we sent
    /// (``matchesEndpoint(of:)``, shared with ``ReachFive/interceptUrl(_:)``) and carries a `code` or an
    /// `error` parameter. Comparing the scheme and the path we declared
    /// is enough to tell our callback apart from the app's other links.
    nonisolated static func isOurCallback(_ url: URL, expectedCallback expected: URL) -> Bool {
        url.matchesEndpoint(of: expected)
            && (url.queryValue("code") != nil || url.queryValue("error") != nil)
    }

    /// Maps an `ASWebAuthenticationSession` error onto a `ReachFiveError`. Pure: the raw error is logged by
    /// `handleSessionCompletion(id:callbackURL:error:)`, which knows whether it is about to be delivered.
    ///
    /// `canceledLogin` is not only "the user tapped Cancel": the system also reports it when the app is not
    /// associated with the host of an `.https` callback, and when a sheet is closed by `cancel()` — measured
    /// on iOS and Mac Catalyst. Only `localizedDescription` tells the three apart.
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
