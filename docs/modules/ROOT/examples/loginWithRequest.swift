Task {
    do {
        let loginFlow = try await AppDelegate.reachfive().login(withRequest: NativeLoginRequest(anchor: window), usingModalAuthorizationFor: [.Passkey, .Password, .SignInWithApple], display: .IfImmediatelyAvailableCredentials)
        // handle successful auth or MFA challenge
    } catch ReachFiveError.AuthCanceled {
        return // No credentials are available. If called at app launch, do nothing. If called in `viewDidAppear`, presents other options for the user to login.
    } catch {
        // Real failure.
    }
}
