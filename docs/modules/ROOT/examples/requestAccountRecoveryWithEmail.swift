AppDelegate
    .reachfive()
    .requestAccountRecovery(
        email: "john.doe@gmail.com",
        redirectUrl: "reachfive-clientId://account-recovery",
    )
    .onSuccess { _ in
        // Do something
    }
    .onFailure { error in
        // Return a ReachFive error
    }
