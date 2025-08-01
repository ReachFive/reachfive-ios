import AuthenticationServices


func webAuthenticationSession(url: URL, callbackURLScheme: String, presentationContextProvider: ASWebAuthenticationPresentationContextProviding, prefersEphemeralWebBrowserSession: Bool) async throws -> URL {
    
    return try await withCheckedThrowingContinuation { continuation in
        // Initialize the session.
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackURLScheme) { callbackURL, error in
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
        
        // Set an appropriate context provider instance that determines the window that acts as a presentation anchor for the session
        session.presentationContextProvider = presentationContextProvider
        session.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
        
        // Start the Authentication Flow
        // if the result of this method is false then the error will already have been processed and the promise failed in the callback
        Task { @MainActor in
            session.start()
        }
    }
}
