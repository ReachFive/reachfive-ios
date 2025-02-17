AppDelegate
    .reachfive()
    .requestAccountRecovery(
        phoneNumber: "+33682234940",
        redirectUrl: "https://example-password-reset.com"
    )
    .onSuccess { _ in
        // Do something
    }
    .onFailure { error in
        // Return a ReachFive error
    }
