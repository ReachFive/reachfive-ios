import Reach5

let freshProfileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login (less than 5 min)

Task {
    do {
        try await AppDelegate.reachfive().updatePassword(
            .FreshAccessTokenParams(
                authToken: freshProfileAuthToken,
                password: "ZPf7LFtc"
            )
        )
        // Do something
    } catch {
        // Return a ReachFive error
    }
}