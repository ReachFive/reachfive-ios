do {
    try await AppDelegate.reachfive().deleteWebAuthnRegistration(id: id, authToken: profileAuthToken)
    // Do something
} catch {
    // Return a ReachFive error
}