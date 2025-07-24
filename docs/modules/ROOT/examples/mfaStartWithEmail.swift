import Reach5

do {
    let response = try await AppDelegate.reachfive().mfaStart(
        registering: .Email(redirectUri: "reachfive-${clientId}://callback"),
        authToken: profileAuthToken
    )
    // Do something
} catch {
    // Return a ReachFive error
}