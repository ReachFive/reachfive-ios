import IdentitySdkCore

let providerName: String = // Here paste the name of the provider

let scope = ["openid", "email", "profile", "phone", "full_write", "offline_access"]

AppDelegate
    .reachfive()
    .getProvider(name: providerName)?
    .login(
        scope: scope,
        origin: "home",
        viewController: self
    )
    .onSuccess{ authToken in
        // Get the profile's authentication token
    }
    .onFailure { error in
        // Return a ReachFive error
    }