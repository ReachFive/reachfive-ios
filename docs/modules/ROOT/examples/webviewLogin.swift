AppDelegate
    .reachfive()
    .webviewLogin(WebviewLoginRequest(
        state: "zf3ifjfmdkj",
        nonce: "n-0S6_PzA3Ze",
        scope: ["openid", "profile", "email"],
        presentationContextProvider: self
    ))
    .onSuccess{ authToken in
        // Get the profile's authentication token
    }
    .onFailure { error in
        // Return a ReachFive error
    }
