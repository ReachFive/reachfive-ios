AppDelegate
    .reachfive()
    .resetPasskeys(withRequest: ResetPasskeyRequest(anchor: window, email: email, friendlyName: friendlyName), verificationCode: verificationCode)
    
    // on success
    .onSuccess { 
        // handle success
    }
    // return ReachFive error on failure
    .onFailure { error in
    }