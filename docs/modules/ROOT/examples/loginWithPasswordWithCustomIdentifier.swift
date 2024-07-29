AppDelegate
    .reachfive()
    .loginWithPassword(
        customIdentifier: "coolCat55",
        password: "UCrcF4RH",
        scope: ["openid", "profile", "email"]
    )
    .onSuccess{ authToken in
        // Get the profile's authentication token
    }
    .onFailure { error in
        // Return a ReachFive error
    }
