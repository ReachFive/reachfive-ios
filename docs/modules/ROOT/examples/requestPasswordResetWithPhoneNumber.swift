AppDelegate
    .reachfive()
    .requestPasswordReset(phoneNumber: "+33682234940")
    .onSuccess{ _ in
        // Do something
    }
    .onFailure { error in
        // Return a ReachFive error
    }