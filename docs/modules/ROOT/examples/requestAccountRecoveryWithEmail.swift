AppDelegate
    .reachfive()
    .requestAccountRecovery(
        email: "john.doe@gmail.com",
        redirectUrl: "https://example-password-reset.com"
    )
    .onSuccess { _ in
        // Do something
    }
    .onFailure { error in
        // Return a ReachFive error
    }
