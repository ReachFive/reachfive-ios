import Reach5

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

do {
    try await AppDelegate.reachfive().updatePassword(
        .AccessTokenParams(
            authToken: profileAuthToken,
            password: "ZPf7LFtc",
            oldPassword: "gVc7piBn"
        )
    )
    // Do something
} catch {
    // Return a ReachFive error
}