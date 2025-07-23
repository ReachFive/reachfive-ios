import Reach5

let providerName: String = // Here paste the name of the provider

let scope = ["openid", "email", "profile", "phone", "full_write", "offline_access"]

Task {
    do {
        if let provider = AppDelegate.reachfive().getProvider(name: providerName) {
            let authToken = try await provider.login(
                scope: scope,
                origin: "home",
                viewController: self
            )
            // Get the profile's authentication token
        }
    } catch {
        // Return a ReachFive error
    }
}