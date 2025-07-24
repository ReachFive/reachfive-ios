import Reach5

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

do {
    try await AppDelegate.reachfive().verifyEmail(
        authToken: profileAuthToken,
        email: "johnatthan.doe@gmail.com",
        code: "123456"
    )
    // Successfully verified email
} catch {
    // Return a ReachFive error
}