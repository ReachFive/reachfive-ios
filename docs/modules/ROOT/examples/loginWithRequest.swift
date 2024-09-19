AppDelegate
    .reachfive()
    .login(withRequest: NativeLoginRequest(anchor: window), usingModalAuthorizationFor: [.Passkey, .Password, .SignInWithApple], display: .IfImmediatelyAvailableCredentials)

    // get auth token on success
    .onSuccess { authToken in
    }
    .onFailure { error in
        switch error {
        case .AuthCanceled: return // No credentials are available. If called at app launch, do nothing. If called in `viewDidAppear`, presents other options for the user to login.
        default: return // Real failure.
        }
    }
