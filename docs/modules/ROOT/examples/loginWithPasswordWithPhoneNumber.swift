AppDelegate
    .reachfive()
    .loginWithPassword(
        phoneNumber: "+33682234940",
        password: "UCrcF4RH",
        scope: ["openid", "profile", "email"]
    )
    .onSuccess{ authToken in
        // Get the profile's authentication token
    }
    .onFailure { error in
        // Return a ReachFive error
    }