import AuthenticationServices

// By marking this entire function with @MainActor, we ensure that the `session.start()`
// call is made within the same structured concurrency context as the caller.
// This avoids creating a detached, unstructured `Task` which would not propagate
// cancellation and could lead to the authentication session starting unnecessarily
// if the parent task was cancelled.
@MainActor
func webAuthenticationSession(url: URL, callbackURLScheme: String, presentationContextProvider: ASWebAuthenticationPresentationContextProviding, prefersEphemeralWebBrowserSession: Bool) async throws -> URL {

    return try await withCheckedThrowingContinuation { continuation in
        // A flag to ensure the continuation is resumed only once.
        // ASWebAuthenticationSession's completion handler can be called multiple times in some edge cases.
        var hasResumed = false

        // Initialize the session.
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackURLScheme) { callbackURL, error in
            // Ensure that all logic is executed on the main thread to prevent race conditions.
            Task { @MainActor in
                guard !hasResumed else {
                    // Already resumed, so we can ignore this call.
                    return
                }
                hasResumed = true

                if let error {
                    let r5Error: ReachFiveError = switch error._code {
                    case 1: .AuthCanceled
                    case 2: .TechnicalError(reason: "Presentation Context Not Provided")
                    case 3: .TechnicalError(reason: "Presentation Context Invalid")
                    default:.TechnicalError(reason: "Unknown Error \(error.localizedDescription)")
                    }
                    continuation.resume(throwing: r5Error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: ReachFiveError.TechnicalError(reason: "No callback URL"))
                    return
                }
                continuation.resume(returning: callbackURL)
            }
        }

        // Set an appropriate context provider instance that determines the window that acts as a presentation anchor for the session
        session.presentationContextProvider = presentationContextProvider
        session.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession

        // Start the Authentication Flow
        if !session.start() {
            // Log the error for debugging purposes.
            #if DEBUG
            print("WebAuthentication session failed to start.")
            #endif
            // If start() returns false, the completion handler might not be called.
            // We need to resume the continuation with an error.
            guard !hasResumed else {
                return
            }
            hasResumed = true
            continuation.resume(throwing: ReachFiveError.TechnicalError(reason: "ASWebAuthenticationSession failed to start"))
        }
    }
}
