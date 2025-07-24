import Reach5

let profileAuthToken: AuthToken = // Here paste the authorization token of the profile retrieved after login

do {
    try await AppDelegate.reachfive().verifyPhoneNumber(
        authToken: profileAuthToken,
        phoneNumber: "+33750253354",
        verificationCode: "501028"
    )
    // Do something
} catch {
    // Return a ReachFive error
}