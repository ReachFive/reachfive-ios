import Reach5

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

Task {
    do {
        let profile = try await AppDelegate.reachfive().getProfile(authToken: profileAuthToken)
        // Get the profile
    } catch {
        // Return a ReachFive error
    }
}