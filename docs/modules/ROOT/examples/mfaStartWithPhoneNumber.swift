import Reach5

do {
    let response = try await AppDelegate.reachfive().mfaStart(
        registering: .PhoneNumber(phoneNumber: "+3531235555"),
        authToken: profileAuthToken
    )
    // Do something
} catch {
    // Return a ReachFive error
}