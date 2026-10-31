import Reach5

do {
    try await AppDelegate.reachfive().startPasswordless(.Email(
        email: "john.doe@gmail.com",
        redirectUri: URL(string: "reachfive-${clientId}://callback")!
    ), scope: ["openid", "email", "offline_access"])
    // Do something
} catch {
    // Return a ReachFive error
}