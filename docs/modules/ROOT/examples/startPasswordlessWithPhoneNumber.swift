import Reach5

do {
    try await AppDelegate.reachfive().startPasswordless(.PhoneNumber(
        phoneNumber: "+33792244940",
        redirectUri: URL(string: "reachfive-${clientId}://callback")!
    ))
    // Do something
} catch {
    // Return a ReachFive error
}