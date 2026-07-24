do {
    try await AppDelegate.reachfive().requestAccountRecovery(
        phoneNumber: "+33682234940",
        redirectUrl: URL(string: "https://example-password-reset.com")!
    )
    // Do something
} catch {
    // Return a ReachFive error
}