AppDelegate
    .reachfive()
    .login(withRequest: NativeLoginRequest(anchor: window), usingModalAuthorizationFor: [.Passkey], display: .IfImmediatelyAvailableCredentials)
    
    // get auth token on success
    .onSuccess { authToken in
    }
    // return ReachFive error on failure
    .onFailure { error in
    }