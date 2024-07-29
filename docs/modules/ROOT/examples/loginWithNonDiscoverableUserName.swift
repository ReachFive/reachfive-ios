AppDelegate
    .reachfive()
    .login(withNonDiscoverableUsername: .Unspecified(username), forRequest: NativeLoginRequest(anchor: window), usingModalAuthorizationFor: [.Passkey], display: .Always)
    
    // get auth token on success
    .onSuccess { authToken in
    }
    // return ReachFive error on failure
    .onFailure { error in
    }