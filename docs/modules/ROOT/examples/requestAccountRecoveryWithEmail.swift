do {
    try await AppDelegate.reachfive().requestAccountRecovery(
        email: "john.doe@gmail.com",
        redirectUrl: URL(string: "reachfive-clientId://account-recovery")!
    )
    // Do something
} catch {
    // Return a ReachFive error
}