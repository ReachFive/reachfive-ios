AppDelegate
    .reachfive()
    .registerNewPasskey(withRequest: NewPasskeyRequest(anchor: window, friendlyName: friendlyName), authToken: authToken)
    
    // get auth token on success
    .onSuccess { authToken in
    }
    // return ReachFive error on failure
    .onFailure { error in
    }