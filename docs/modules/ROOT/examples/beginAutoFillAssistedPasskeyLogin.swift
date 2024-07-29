AppDelegate
    .reachfive()
    .beginAutoFillAssistedPasskeyLogin(withRequest: NativeLoginRequest(anchor: window))
    
    // get auth token on success
    .onSuccess { authToken in
    }
    // return ReachFive error on failure
    .onFailure { error in
    }