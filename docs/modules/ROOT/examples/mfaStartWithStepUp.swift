import Reach5

let scope = ["openid", "email", "profile", "phone", "full_write", "offline_access"]

do {
    let response = try await AppDelegate.reachfive().mfaStart(
        stepUp: .AuthTokenFlow(
            authType: "email",
            authToken: profileAuthToken,
            scope: scope
        )
    )
    // Do something
} catch {
    // Return a ReachFive error
}