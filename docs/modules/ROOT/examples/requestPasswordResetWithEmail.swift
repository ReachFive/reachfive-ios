AppDelegate
    .reachfive()
    .requestPasswordReset(
        email: "john.doe@gmail.com",
        redirectUrl: "reachfive-clientId://password-reset"
    )
    .onSuccess { _ in
        // Do something
    }
    .onFailure { error in
        // Return a ReachFive error
    }
