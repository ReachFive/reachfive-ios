import IdentitySdkCore

AppDelegate
    .reachfive()
    .signupWithWebAuthn(
        profile: ProfileWebAuthnSignupRequest(
            email: "john.doe@gmail.com",
            givenName: "John",
            familyName: "Doe"
        ),
        origin: "https://dev-sandbox-268508.web.app",
        friendlyName: "iPhone 11",
        scopes: ["openid", "email", "profile", "phone", "full_write", "offline_access"],
        viewController: self
    )
    .onSuccess { authToken in
        // Get the profile's authentication token
    }
    .onFailure { error in
        // Return a ReachFive error
    }
