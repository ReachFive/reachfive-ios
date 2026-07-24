import Reach5

do {
    try await AppDelegate.reachfive().startPasswordless(.Email(
        email: "john.doe@gmail.com",
        redirectUri: URL(string: "reachfive-${clientId}://callback")!
    ))
    // Do something
} catch {
    // Return a ReachFive error
}