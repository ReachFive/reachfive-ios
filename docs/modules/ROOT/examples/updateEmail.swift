import Reach5

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

Task {
    do {
        let updatedProfile = try await AppDelegate.reachfive().updateEmail(
            authToken: profileAuthToken,
            email: "johnatthan.doe@gmail.com",
            redirectUrl: "https://example-email-update.com"
        )
        // Get the updated profile
    } catch {
        // Return a ReachFive error
    }
}
