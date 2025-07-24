import Reach5

do {
    let authToken = try await AppDelegate.reachfive().signup(withRequest: PasskeySignupRequest(passkeyProfile: profile, friendlyName: username, anchor: window))
    // Get the profile's authentication token
} catch {
    // Return a ReachFive error
}