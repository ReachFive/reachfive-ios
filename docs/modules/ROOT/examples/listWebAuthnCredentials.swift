do {
    let listCredentials = try await AppDelegate.reachfive().listWebAuthnCredentials(authToken: profileAuthToken)
    // Get the list of devices
} catch {
    // Return a ReachFive error
}