import Reach5

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

do {
    try await AppDelegate.reachfive().updatePassword(
        .AccessTokenParams(
            authToken: profileAuthToken,
            oldPassword: "gVc7piBn",
            password: "ZPf7LFtc"
        )
    )
    // Do something
} catch {
    // Return a ReachFive error
}