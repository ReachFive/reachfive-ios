import IdentitySdkCore

AppDelegate
    .reachfive()
    .loginWithWebAuthn(
        email: "john.doe@gmail.com",
        origin: "https://dev-sandbox-268508.web.app",
        scopes: ["openid", "email", "profile", "phone", "full_write", "offline_access"],
        viewController: self
    )
    .onSuccess { authToken in
        // Get the profile's authentication token
    }
    .onFailure { error in
        // Return a ReachFive error
    }
