import AuthenticationServices

/// Owns an `ASWebAuthenticationSession` and the continuation that awaits its result.
///
/// Beyond the usual case (the session completes itself via its callback URL scheme), this can also
/// be completed **out-of-band** via ``complete(externalCallbackURL:)`` — for providers that end their
/// flow on a universal link delivered to the app through `application(_:continue:)` while the session
/// is still open (e.g. an external app reopens the host app). The session is then cancelled.
///
/// A session is **single-use**: create a new instance for each authentication attempt. The one-shot
/// `hasResumed` guard is never reset — so a duplicate or late `ASWebAuthenticationSession` callback
/// (which can fire more than once) can never resume a continuation twice.
/// Reusing an instance for a second login would leave it permanently completed.
///
/// Marked `@MainActor` so `session.start()` / `cancel()` always run on the main thread.
@MainActor
final class WebAuthenticationSession {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    // ASWebAuthenticationSession's completion handler can fire more than once in edge cases, and an
    // external completion can race the cancellation callback: only the first resolution wins.
    private var hasResumed = false

    nonisolated init() {}

    func start(url: URL,
               routing: WebAuthRouting,
               callbackURLScheme: String,
               presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
               prefersEphemeralWebBrowserSession: Bool = false) async throws -> URL {

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let completionHandler: ASWebAuthenticationSession.CompletionHandler = { [weak self] callbackURL, error in
                // Ensure all logic runs on the main thread to prevent race conditions.
                Task { @MainActor in
                    self?.handleSessionCompletion(callbackURL: callbackURL, error: error)
                }
            }

            let session: ASWebAuthenticationSession
            // iOS 17.4+ : quand le redirect_uri est un universal link (https), on intercepte la
            // redirection in-band directement dans la session via le callback `.https` (nécessite
            // l'Associated Domain `webcredentials:<host>`). Sinon, scheme custom (legacy, iOS < 17.4).
            if #available(iOS 17.4, *),
               let expectedCallback = routing.expectedCallback,
               expectedCallback.scheme == "https",
               let host = expectedCallback.host {
                session = ASWebAuthenticationSession(
                    url: url,
                    callback: .https(host: host, path: expectedCallback.path),
                    completionHandler: completionHandler)
            } else {
                session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: callbackURLScheme,
                    completionHandler: completionHandler)
            }

            // Set an appropriate context provider instance that determines the window that acts as a presentation anchor for the session
            session.presentationContextProvider = presentationContextProvider
            session.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
            self.session = session

            // Start the Authentication Flow
            if !session.start() {
                // Log the error for debugging purposes.
                #if DEBUG
                print("WebAuthentication session failed to start.")
                #endif
                // If start() returns false, the completion handler might not be called.
                // We need to resume the continuation with an error.
                complete(.failure(ReachFiveError.TechnicalError(reason: "ASWebAuthenticationSession failed to start")))
            }
        }
    }

    /// Completes the awaiting `start(...)` with a callback URL obtained outside the session (a universal
    /// link received via `application(_:continue:)`), and cancels the still-open session.
    func complete(externalCallbackURL url: URL) {
        // Capture `session` before `complete(_:)`, which nils it out; otherwise we'd lose the reference
        // needed to cancel the still-open session. Cancelling after resuming is fine: the cancellation
        // callback is ignored thanks to the `hasResumed` guard.
        let runningSession = session
        complete(.success(url))
        runningSession?.cancel()
    }

    private func handleSessionCompletion(callbackURL: URL?, error: Error?) {
        if let error {
            complete(.failure(Self.reachFiveError(for: error)))
        } else if let callbackURL {
            complete(.success(callbackURL))
        } else {
            complete(.failure(ReachFiveError.TechnicalError(reason: "No callback URL")))
        }
    }

    private func complete(_ result: Result<URL, Error>) {
        guard !hasResumed, let continuation else { return }
        hasResumed = true
        self.continuation = nil
        self.session = nil
        continuation.resume(with: result)
    }

    /// Mappe une erreur d'`ASWebAuthenticationSession` vers une `ReachFiveError`.
    nonisolated static func reachFiveError(for error: Error) -> ReachFiveError {
        switch error._code {
        case 1: .AuthCanceled
        case 2: .TechnicalError(reason: "Presentation context not provided: \(error.localizedDescription)")
        case 3: .TechnicalError(reason: "Presentation context invalid: \(error.localizedDescription)")
        default: .TechnicalError(reason: "Unknown Error \(error.localizedDescription)")
        }
    }
}
